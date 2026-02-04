// lib/services/mfiles_service.dart
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mfiles_app/models/group_filter.dart';
import 'package:mfiles_app/models/linked_object_item.dart';
import 'package:mfiles_app/models/view_content_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';

import '../models/vault_object_type.dart';
import '../models/object_class.dart';
import '../models/class_property.dart';
import '../models/lookup_item.dart';
import '../models/object_creation_request.dart';
import '../models/vault.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import '../models/object_file.dart';
import '../models/object_comment.dart';

class MFilesService extends ChangeNotifier {
  // Auth
  String? accessToken;
  String? refreshToken;
  String? username;
  int? userId; // Auth system user ID
  int? mfilesUserId; // M-Files user ID (vault-scoped)

  // Vault
  Vault? selectedVault;
  List<Vault> vaults = [];

  // Object types and classes
  List<VaultObjectType> objectTypes = [];
  List<ObjectClass> objectClasses = [];
  final Map<int, ObjectClassesResponse> _classesByObjectType = {};

  // Class properties
  List<ClassProperty> classProperties = [];

  // Deleted objects
  List<ViewObject> deletedObjects = [];

  // Report objects
  List<ViewObject> reportObjects = [];

  // Views / objects
  List<ViewItem> allViews = [];
  List<ViewItem> commonViews = [];
  List<ViewItem> otherViews = [];

  List<ViewObject> recentObjects = [];
  List<ViewObject> assignedObjects = [];
  List<ViewObject> searchResults = []; // search no longer overwrites recent

  String currentTab = 'Home';

  // Loading/Error
  bool isLoading = false;
  String? error;

  static const String baseUrl = 'https://api.alignsys.tech';

  void _setLoading(bool loading) {
    isLoading = loading;
    notifyListeners();
  }

  void _setError(String? err) {
    error = err;
    notifyListeners();
  }

  void clearError() => _setError(null);

  Map<String, String> get _authHeaders {
    if (accessToken == null) return const <String, String>{};
    return {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
      'accept': '*/*',
    };
  }

  Map<String, String> get _authHeadersNoJson {
    if (accessToken == null) return const <String, String>{};
    return {
      'Authorization': 'Bearer $accessToken',
      'accept': '*/*',
    };
  }

  String get vaultGuidWithBraces {
    if (selectedVault == null) throw Exception('No vault selected');
    return selectedVault!.guid;
  }

  String get vaultGuidNoBraces {
    if (selectedVault == null) throw Exception('No vault selected');
    return selectedVault!.guid.replaceAll(RegExp(r'[{}]'), '');
  }

  int get currentUserId {
    if (mfilesUserId == null) throw Exception('M-Files User ID is not set');
    return mfilesUserId!;
  }

  int? _decodeJwtAndGetUserId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payloadMap = json.decode(decoded) as Map<String, dynamic>;
      return payloadMap['user_id'] as int?;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveTokens(
    String access,
    String refresh, {
    String? user,
    int? userIdValue,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('access_token', access);
    await prefs.setString('refresh_token', refresh);

    accessToken = access;
    refreshToken = refresh;

    if (user != null) {
      await prefs.setString('username', user);
      username = user;
    }
    if (userIdValue != null) {
      await prefs.setInt('user_id', userIdValue);
      userId = userIdValue;
    }
  }

  Future<bool> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('access_token');
    refreshToken = prefs.getString('refresh_token');
    username = prefs.getString('username');
    userId = prefs.getInt('user_id');
    mfilesUserId = prefs.getInt('mfiles_user_id');

    if (userId == null && accessToken != null) {
      userId = _decodeJwtAndGetUserId(accessToken!);
      if (userId != null) await prefs.setInt('user_id', userId!);
    }

    return accessToken != null && refreshToken != null;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('mfiles_user_id');

    accessToken = null;
    refreshToken = null;
    userId = null;
    mfilesUserId = null;
    selectedVault = null;

    vaults.clear();
    objectTypes.clear();
    objectClasses.clear();
    _classesByObjectType.clear();

    allViews.clear();
    commonViews.clear();
    otherViews.clear();

    recentObjects.clear();
    assignedObjects.clear();
    searchResults.clear();

    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    final body = {'username': email, 'password': password, 'auth_type': 'email'};

    final response = await http.post(
      Uri.parse('https://auth.alignsys.tech/api/token/'),
      headers: const {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      accessToken = data['access'];
      refreshToken = data['refresh'];

      userId = _decodeJwtAndGetUserId(accessToken!);
      await saveTokens(accessToken!, refreshToken!, user: email, userIdValue: userId);
      return true;
    }

    throw Exception('Login failed: ${response.statusCode}');
  }

  Future<List<Vault>> getUserVaults() async {
    if (accessToken == null) throw Exception("User not logged in");

    final response = await http.get(
      Uri.parse('https://auth.alignsys.tech/api/user/vaults/'),
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      vaults = data.map((v) => Vault.fromJson(v)).toList();
      notifyListeners();
      return vaults;
    }

    throw Exception('Failed to fetch vaults: ${response.statusCode}');
  }

  Future<void> fetchMFilesUserId() async {
    if (selectedVault == null || accessToken == null) return;

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/user/mfiles-profile/$vaultGuidNoBraces'),
        headers: _authHeadersNoJson,
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        mfilesUserId = (data['id'] as num?)?.toInt();

        final prefs = await SharedPreferences.getInstance();
        if (mfilesUserId != null) {
          await prefs.setInt('mfiles_user_id', mfilesUserId!);
        }

        notifyListeners();
        return;
      }

      await _useFallbackMapping();
    } catch (_) {
      await _useFallbackMapping();
    }
  }

  Future<void> _useFallbackMapping() async {
    if (userId == null) return;

    mfilesUserId = (userId == 37) ? 20 : userId;

    final prefs = await SharedPreferences.getInstance();
    if (mfilesUserId != null) {
      await prefs.setInt('mfiles_user_id', mfilesUserId!);
    }

    notifyListeners();
  }

  Future<void> fetchObjectTypes() async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/MfilesObjects/GetVaultsObjects/$vaultGuidWithBraces/$mfilesUserId',
      );

      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        objectTypes = data.map((e) => VaultObjectType.fromJson(e)).toList();
      } else {
        _setError('Failed to fetch object types: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching object types: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchObjectClasses(int objectTypeId) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/MfilesObjects/GetObjectClasses/$vaultGuidWithBraces/$objectTypeId/$mfilesUserId',
      );

      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final parsed = ObjectClassesResponse.fromJson(json.decode(response.body));
        _classesByObjectType[objectTypeId] = parsed;

        objectClasses = [
          ...parsed.unGrouped,
          ...parsed.grouped.expand((g) => g.members),
        ];
      } else {
        _setError('Failed to fetch object classes: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching object classes: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchClassProperties(int objectTypeId, int classId) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/MfilesObjects/ClassProps/$vaultGuidWithBraces/$objectTypeId/$classId/$mfilesUserId',
      );

      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        classProperties = data.map((e) => ClassProperty.fromJson(e)).toList();
      } else {
        _setError('Failed to fetch class properties: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching class properties: $e');
    } finally {
      _setLoading(false);
    }
  }

  bool isClassInAnyGroup(int classId) {
    for (final resp in _classesByObjectType.values) {
      for (final group in resp.grouped) {
        if (group.members.any((c) => c.id == classId)) return true;
      }
    }
    return false;
  }

  List<ClassGroup> getClassGroupsForType(int objectTypeId) {
    return _classesByObjectType[objectTypeId]?.grouped ?? [];
  }

  Future<void> searchVault(String query) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final encodedQuery = Uri.encodeComponent(query);
      final url = Uri.parse(
        '$baseUrl/api/objectinstance/Search/$vaultGuidWithBraces/$encodedQuery/$mfilesUserId',
      );

      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        searchResults = data.map((e) => ViewObject.fromJson(e)).toList();
        notifyListeners();
      } else {
        _setError('Search failed: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Search error: $e');
    } finally {
      _setLoading(false);
    }
  }

  void clearSearchResults() {
    searchResults = [];
    notifyListeners();
  }

  Future<String?> uploadFile(File file) async {
    _setLoading(true);
    _setError(null);

    try {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/objectinstance/FilesUploadAsync'),
      );

      request.files.add(await http.MultipartFile.fromPath('formFiles', file.path));
      request.headers['Authorization'] = 'Bearer $accessToken';

      final response = await request.send();
      final body = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        return json.decode(body)['uploadID'];
      }

      _setError('File upload failed: ${response.statusCode}');
      return null;
    } catch (e) {
      _setError('Error uploading file: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  Future<List<LookupItem>> fetchLookupItems(int propertyId) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return [];

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/ValuelistInstance/$vaultGuidWithBraces/$propertyId/$mfilesUserId',
      );

      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((e) => LookupItem.fromJson(e)).toList();
      }

      _setError('Failed to fetch lookup items: ${response.statusCode}');
      return [];
    } catch (e) {
      _setError('Error fetching lookup items: $e');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> createObject(ObjectCreationRequest request) async {
    _setLoading(true);
    _setError(null);

    try {
      if (selectedVault == null) return false;
      if (accessToken == null) return false;
      if (mfilesUserId == null) return false;

      final url = Uri.parse('$baseUrl/api/objectinstance/ObjectCreation');

      final body = <String, dynamic>{
        "objectID": request.objectID,
        "classID": request.classID,
        "properties": request.properties.map((p) => p.toJson()).toList(),
        "vaultGuid": vaultGuidWithBraces,
        "userID": mfilesUserId,
      };

      final up = (request.uploadId ?? '').trim();
      if (up.isNotEmpty) body["uploadId"] = up;

      final response = await http.post(
        url,
        headers: _authHeaders,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200 || response.statusCode == 201) return true;

      _setError('Server returned ${response.statusCode}: ${response.body}');
      return false;
    } catch (e) {
      _setError('Error creating object: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchAllViews() async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse('$baseUrl/api/Views/GetViews/$vaultGuidWithBraces/$mfilesUserId');
      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as Map<String, dynamic>;

        commonViews = (data['commonViews'] as List? ?? [])
            .map((e) => ViewItem.fromJson(e))
            .toList();

        otherViews = (data['otherViews'] as List? ?? [])
            .map((e) => ViewItem.fromJson(e))
            .toList();

        allViews = [...commonViews, ...otherViews];
        notifyListeners();
      } else {
        _setError('Failed to fetch views: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching views: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchRecentObjects() async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse('$baseUrl/api/Views/GetRecent/$vaultGuidWithBraces/$mfilesUserId');
      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        final fetched = data.map((e) => ViewObject.fromJson(e as Map<String, dynamic>)).toList();

        fetched.sort((a, b) {
          final ad = a.lastModifiedUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.lastModifiedUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        });

        recentObjects = fetched;
        notifyListeners();
      } else {
        _setError('Failed to fetch recent objects: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching recent objects: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchAssignedObjects() async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse('$baseUrl/api/Views/GetAssigned/$vaultGuidWithBraces/$mfilesUserId');
      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        assignedObjects = data.map((e) => ViewObject.fromJson(e)).toList();
        notifyListeners();
      } else {
        _setError('Failed to fetch assigned objects: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching assigned objects: $e');
    } finally {
      _setLoading(false);
    }
  }

  void setActiveTab(String tab) {
    currentTab = tab;
    notifyListeners();
  }

  Future<List<Map<String, dynamic>>> fetchObjectViewProps({
    required int objectId,
    required int classId,
  }) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse(
      '$baseUrl/api/objectinstance/GetObjectViewProps/'
      '$vaultGuidWithBraces/$objectId/$classId/$mfilesUserId',
    );

    final resp = await http.get(url, headers: _authHeadersNoJson);

    if (resp.statusCode != 200) {
      throw Exception('GetObjectViewProps failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = json.decode(resp.body);
    if (decoded is List) return decoded.cast<Map<String, dynamic>>();
    if (decoded is Map && decoded['props'] is List) return (decoded['props'] as List).cast<Map<String, dynamic>>();
    if (decoded is Map && decoded['properties'] is List) return (decoded['properties'] as List).cast<Map<String, dynamic>>();

    throw Exception('Unexpected GetObjectViewProps shape: ${resp.body}');
  }

  Future<bool> updateObjectProps({
    required int objectId,
    required int objectTypeId,
    required int classId,
    required List<Map<String, dynamic>> props,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      if (selectedVault == null) return false;
      if (accessToken == null) return false;
      if (mfilesUserId == null) return false;

      final url = Uri.parse('$baseUrl/api/objectinstance/UpdateObjectProps');

      final body = {
        "objectid": objectId,
        "objectypeid": objectTypeId,
        "objecttypeid": objectTypeId,
        "classid": classId,
        "props": props.map((p) {
          return {
            "id": p["id"],
            "value": (p["value"] ?? "").toString(),
            "datatype": (p["datatype"] ?? "MFDatatypeText")
                .toString()
                .replaceAll('MFDataType', 'MFDatatype'),
          };
        }).toList(),
        "vaultGuid": vaultGuidWithBraces,
        "userID": mfilesUserId,
      };

      final resp = await http.put(
        url,
        headers: _authHeaders,
        body: jsonEncode(body),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) return true;

      _setError('Server returned ${resp.statusCode}: ${resp.body}');
      return false;
    } catch (e) {
      _setError('Error updating object: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<List<ObjectFile>> fetchObjectFiles({
    required int objectId,
    required int classId,
  }) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse(
      '$baseUrl/api/objectinstance/GetObjectFiles/'
      '$vaultGuidWithBraces/$objectId/$classId',
    );

    debugPrint('📦 GetObjectFiles args: objectId=$objectId classId=$classId vault=$vaultGuidWithBraces');

    final resp = await http.get(url, headers: _authHeadersNoJson);

    if (resp.statusCode == 404) return <ObjectFile>[];

    if (resp.statusCode != 200) {
      throw Exception('GetObjectFiles failed: ${resp.statusCode} ${resp.body}');
    }

    final data = json.decode(resp.body) as List;
    return data.map((e) => ObjectFile.fromJson(e as Map<String, dynamic>)).toList();
  }

  Object? _pickAnyKeyCI(Map m, String key) {
    final target = key.trim().toLowerCase();

    // Build normalized -> actualKey map using key.toString()
    for (final k in m.keys) {
      final norm = k.toString().trim().toLowerCase();
      if (norm == target) return m[k];
    }

    return null;
  }

  String? _extractStringByKeysCI(Map m, List<String> keys) {
    for (final k in keys) {
      final v = _pickAnyKeyCI(m, k);
      if (v is String && v.trim().isNotEmpty) return v;
    }
    return null;
  }

  String? _extractBase64Flexible(Map m) {
    final v = _pickAnyKeyCI(m, 'base64');

    // Most common: base64 is a String
    if (v is String) return v;

    // Sometimes: { base64: { value: "..." } } or similar
    if (v is Map) {
      final nested = _extractStringByKeysCI(v, ['value', 'data', 'content', 'base64']);
      if (nested != null) return nested;
    }

    // Sometimes: base64 is a list of strings/chunks
    if (v is List) {
      final parts = v.whereType<String>().toList();
      if (parts.isNotEmpty) return parts.join();
    }

    // Last resort: recursively search the whole JSON for a base64-looking string
    return _deepFindBase64(m);
  }

  String? _deepFindBase64(dynamic node) {
    if (node is String) {
      final s = node.trim();
      // heuristic: long-ish and base64-ish
      final looks =
          s.length > 100 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s);
      return looks ? s : null;
    }

    if (node is List) {
      for (final x in node) {
        final found = _deepFindBase64(x);
        if (found != null) return found;
      }
    }

    if (node is Map) {
      // if any key is base64-like, prioritize it
      for (final e in node.entries) {
        if (e.key is String && (e.key as String).trim().toLowerCase() == 'base64') {
          final found = _deepFindBase64(e.value);
          if (found != null) return found;
        }
      }
      // otherwise search everything
      for (final e in node.entries) {
        final found = _deepFindBase64(e.value);
        if (found != null) return found;
      }
    }

    return null;
  }


  Future<({List<int> bytes, String? contentType})> _getBytes(Uri url) async {
    final resp = await http.get(url, headers: _authHeadersNoJson);

    if (resp.statusCode != 200) {
      throw Exception('${resp.statusCode} ${resp.body}');
    }

    final contentType = resp.headers['content-type'];
    final bodyBytes = resp.bodyBytes;

    // If server returns a JSON wrapper, decode base64 from it.
    final isJson = (contentType?.toLowerCase().contains('application/json') ?? false) ||
        _looksLikeJson(bodyBytes);

    if (isJson) {
      final text = utf8.decode(bodyBytes);
      final dynamic j = jsonDecode(text);

      if (j is! Map) {
        throw Exception('JSON returned but not an object.');
      }

      // Case-insensitive base64 extraction + tolerate different shapes.
      final base64Value = _extractBase64Flexible(j);

      if (base64Value == null || base64Value.trim().isEmpty) {
        final base64Field = _pickAnyKeyCI(j, 'base64');
        throw Exception(
          'JSON returned but base64 not extractable. '
          'base64Type=${base64Field?.runtimeType} keys=${j.keys.toList()}',
        );
      }

      final cleaned = base64Value.contains(',')
          ? base64Value.split(',').last.trim()
          : base64Value.trim();

      final decoded = base64Decode(cleaned);
      final ctFromJson = _extractStringByKeysCI(j, ['contentType', 'content-type', 'mime', 'mimeType']);
      return (bytes: decoded, contentType: ctFromJson);
    }

    // Otherwise it's raw bytes already.
    return (bytes: bodyBytes, contentType: contentType);
  }

  bool _looksLikeJson(List<int> bytes) {
    // Cheap check: skip whitespace then look for '{' or '['
    int i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09) {
        i++;
        continue;
      }
      return b == 0x7B /* { */ || b == 0x5B /* [ */;
    }
    return false;
  }

  String? _pickStringKeyCI(Map m, List<String> keys) {
    for (final k in keys) {
      // direct
      final v = m[k];
      if (v is String) return v;

      // case-insensitive search
      for (final entry in m.entries) {
        if (entry.key is String && (entry.key as String).toLowerCase() == k.toLowerCase()) {
          final vv = entry.value;
          if (vv is String) return vv;
        }
      }
    }
    return null;
  }


  Future<({List<int> bytes, String? contentType})> downloadFileBytesWithFallback({
    required int displayObjectId,
    required int classId,
    required int fileId,
    required String reportGuid,
  }) async {
    if (selectedVault == null || accessToken == null) throw Exception('Session not ready');

    final vg = vaultGuidWithBraces;

    final urlsToTry = <Uri>[
      Uri.parse('$baseUrl/api/objectinstance/DownloadActualFile/$vg/$displayObjectId/$classId/$fileId'),
      Uri.parse('$baseUrl/api/objectinstance/DownloadFile/$vg/$displayObjectId/$classId/$fileId'),
    ];

    final rg = reportGuid.trim();
    if (rg.isNotEmpty) {
      urlsToTry.addAll([
        Uri.parse('$baseUrl/api/objectinstance/DownloadOtherFiles/$vg/$rg'),
        Uri.parse('$baseUrl/api/objectinstance/DownloadOtherFiles/$vg/$displayObjectId/$classId/$fileId'),
        Uri.parse('$baseUrl/api/objectinstance/DownloadOtherFiles/$vg/$displayObjectId/$classId/$fileId/$rg'),
      ]);
    }

    Object? lastErr;
    for (final u in urlsToTry) {
      try {
        return await _getBytes(u);
      } catch (e) {
        lastErr = e;
      }
    }

    throw Exception('All download endpoints failed. Last error: $lastErr');
  }

  String _safeFilename(String title, String extension, int fileId) {
    final ext = extension.trim().toLowerCase().replaceFirst('.', '');
    var base = title.trim().isEmpty ? 'file_$fileId' : title.trim();

    base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    if (ext.isEmpty) return base;

    // Don’t double-append
    if (base.toLowerCase().endsWith('.$ext')) return base;

    return '$base.$ext';
  }


  Future<String> downloadAndOpenFile({
    required int displayObjectId,
    required int classId,
    required int fileId,
    required String fileTitle,
    required String extension,
    required String reportGuid,
  }) async {
    final result = await downloadFileBytesWithFallback(
      displayObjectId: displayObjectId,
      classId: classId,
      fileId: fileId,
      reportGuid: reportGuid,
    );

    
    //Debugging: log the first few bytes and content type to help identify issues with downloaded files (e.g. HTML error pages instead of actual files)
    void _debugSignature(List<int> b, String? ct) {
      bool starts(List<int> s) =>
          b.length >= s.length &&
          List.generate(s.length, (i) => b[i] == s[i]).every((x) => x);

      final sig = [
        if (starts([0x25, 0x50, 0x44, 0x46])) 'PDF',
        if (starts([0xFF, 0xD8, 0xFF])) 'JPG',
        if (starts([0x89, 0x50, 0x4E, 0x47])) 'PNG',
        if (starts([0x50, 0x4B, 0x03, 0x04])) 'ZIP(DOCX/XLSX)',
      ].join(',');

      debugPrint('OPEN bytes=${b.length} ct=$ct sig=$sig');
    }

    _debugSignature(result.bytes, result.contentType);

    final filename = _safeFilename(fileTitle, extension, fileId);

    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';
    final f = File(filePath);
    await f.writeAsBytes(result.bytes, flush: true);

    final opened = await OpenFilex.open(filePath);
    if (opened.type != ResultType.done) {
      throw Exception(opened.message);
    }

    return filePath;
  }

  Future<String> downloadAndSaveFile({
    required int displayObjectId,
    required int classId,
    required int fileId,
    required String fileTitle,
    required String extension,
    required String reportGuid,
  }) async {
    final result = await downloadFileBytesWithFallback(
      displayObjectId: displayObjectId,
      classId: classId,
      fileId: fileId,
      reportGuid: reportGuid,
    );

    final filename = _safeFilename(fileTitle, extension, fileId);

    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$filename';
    final out = File(path);
    await out.writeAsBytes(result.bytes, flush: true);

    return path;
  }

  // -------------------- Deleted / Reports --------------------

  Future<void> fetchDeletedObjects() async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/ObjectDeletion/GetDeletedObject/$vaultGuidWithBraces/$mfilesUserId',
      );

      final resp = await http.get(url, headers: _authHeadersNoJson);

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as List;
        deletedObjects = data
            .whereType<Map<String, dynamic>>()
            .map((e) => ViewObject.fromJson(e))
            .toList();
        notifyListeners();
        return;
      }

      _setError('Failed to fetch deleted objects: ${resp.statusCode} ${resp.body}');
    } catch (e) {
      _setError('Error fetching deleted objects: $e');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> fetchReportObjects() async {
    reportObjects = [];
    notifyListeners();
  }

  // -------------------- View details --------------------

  Future<List<ViewContentItem>> fetchObjectsInViewRaw(int viewId) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse('$baseUrl/api/Views/GetObjectsInView').replace(
      queryParameters: {
        'vaultGuid': vaultGuidWithBraces,
        'viewId': viewId.toString(),
        'userID': mfilesUserId.toString(),
      },
    );

    final resp = await http.get(url, headers: _authHeadersNoJson);

    if (resp.statusCode != 200) {
      throw Exception('GetObjectsInView failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = json.decode(resp.body);

    final List list = decoded is List
        ? decoded
        : (decoded is Map && decoded['items'] is List)
            ? decoded['items'] as List
            : (decoded is Map && decoded['data'] is List)
                ? decoded['data'] as List
                : <dynamic>[];

    return list
        .whereType<Map<String, dynamic>>()
        .map(ViewContentItem.fromJson)
        .toList();
  }

  Future<List<ViewContentItem>> fetchViewPropItems({
      required int viewId,
      required List<GroupFilter> filters,
    }) async {
      if (selectedVault == null || mfilesUserId == null || accessToken == null) {
        throw Exception('Session not ready');
      }

      final url = Uri.parse('$baseUrl/api/Views/GetViewPropObjects');

      final body = {
        "viewId": viewId,
        "userID": mfilesUserId,
        "vaultGuid": vaultGuidWithBraces,
        "properties": filters.map((f) => f.toJson()).toList(),
      };

      if (kDebugMode) {
        debugPrint('🚀 GetViewPropObjects URL: $url');
        debugPrint('📦 Body: ${jsonEncode(body)}');
      }

      final resp = await http.post(
        url,
        headers: _authHeaders,
        body: jsonEncode(body),
      );

      if (kDebugMode) {
        debugPrint('📨 Status: ${resp.statusCode}');
        debugPrint('📨 Body: ${resp.body}');
      }

      if (resp.statusCode != 200) {
        throw Exception('GetViewPropObjects failed: ${resp.statusCode} ${resp.body}');
      }

      final decoded = json.decode(resp.body);
      if (decoded is! List) return <ViewContentItem>[];

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ViewContentItem.fromJson)
          .toList();
  }

  // -------------------- Comments --------------------//
  Future<List<ObjectComment>> fetchComments({
    required int objectId,
    required int objectTypeId,
    required String vaultGuid,
  }) async {
    error = null;

    // ASSUMPTION:
    // GET /api/Comments accepts query params: objectId, objectTypeId, vaultGuid
    // If your backend expects different (headers/body), change here.
    final uri = Uri.parse('$baseUrl/api/Comments').replace(queryParameters: {
      'objectId': objectId.toString(),
      'objectTypeId': objectTypeId.toString(),
      'vaultGuid': vaultGuid,
    });

    final res = await http.get(
      uri,
      headers: {
        'accept': '*/*',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      error = 'HTTP ${res.statusCode}: ${res.body}';
      throw Exception(error);
    }

    final data = jsonDecode(res.body);
    if (data is! List) return [];

    return data
        .whereType<Map<String, dynamic>>()
        .map(ObjectComment.fromJson)
        .toList();
  }

  Future<bool> postComment({
    required String comment,
    required int objectId,
    required int objectTypeId,
    required String vaultGuid,
  }) async {
    error = null;

    final uri = Uri.parse('$baseUrl/api/Comments');

    final payload = {
      "comment": comment,
      "objectId": objectId,
      "vaultGuid": vaultGuid,
      "objectTypeId": objectTypeId,
      // Prefer M-Files user id if you have it, fallback to auth userId
      "userID": (mfilesUserId ?? userId ?? 0),
    };

    final res = await http.post(
      uri,
      headers: {
        'accept': '*/*',
        'content-type': 'application/json',
        if (accessToken != null) 'Authorization': 'Bearer $accessToken',
      },
      body: jsonEncode(payload),
    );

    if (res.statusCode < 200 || res.statusCode >= 300) {
      error = 'HTTP ${res.statusCode}: ${res.body}';
      return false;
    }

    return true;
  }



  // -------------------- Delete object --------------------

  Future<bool> deleteObject({
    required int objectId,
    required int classId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      if (selectedVault == null) return false;
      if (accessToken == null) return false;
      if (mfilesUserId == null) return false;

      final url = Uri.parse('$baseUrl/api/ObjectDeletion/DeleteObject');

      final body = {
        "vaultGuid": vaultGuidWithBraces,
        "objectId": objectId,
        "classId": classId,
        "userID": mfilesUserId,
      };

      final resp = await http.post(
        url,
        headers: _authHeaders,
        body: jsonEncode(body),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) return true;

      _setError('Server returned ${resp.statusCode}: ${resp.body}');
      return false;
    } catch (e) {
      _setError('Error deleting object: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ==================== WORKFLOWS ====================

  // Existing: read current workflow state (or null if none)
  Future<WorkflowInfo?> getObjectWorkflowState({
    required int objectTypeId,
    required int objectId,
  }) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse('$baseUrl/api/WorkflowsInstance/GetObjectworkflowstate');

    final body = {
      "vaultGuid": vaultGuidWithBraces,
      "objectTypeId": objectTypeId,
      "objectId": objectId,
      "userID": mfilesUserId,
    };

    final resp = await http.post(url, headers: _authHeaders, body: jsonEncode(body));

    if (resp.statusCode == 404) return null;

    if (resp.statusCode != 200) {
      throw Exception('GetObjectworkflowstate failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = json.decode(resp.body);
    if (decoded is! Map<String, dynamic>) return null;

    return WorkflowInfo.fromJson(decoded);
  }

  // Existing: next states list for current workflow (backend-defined)
  Future<List<WorkflowStateOption>> getObjectWorkflowAllStates({
    required int objectTypeId,
    required int objectId,
  }) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse('$baseUrl/api/WorkflowsInstance/GetObjectworkflowAllstates');

    final body = {
      "vaultGuid": vaultGuidWithBraces,
      "objectTypeId": objectTypeId,
      "objectId": objectId,
      "userID": mfilesUserId,
    };

    final resp = await http.post(url, headers: _authHeaders, body: jsonEncode(body));

    if (resp.statusCode != 200) {
      throw Exception('GetObjectworkflowAllstates failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = json.decode(resp.body);
    if (decoded is! List) return <WorkflowStateOption>[];

    return decoded.whereType<Map<String, dynamic>>().map(WorkflowStateOption.fromJson).toList();
  }

  // Existing: set workflow state (also used to assign workflow if not present)
  Future<bool> setObjectWorkflowState({
    required int objectTypeId,
    required int objectId,
    required int workflowId,
    required int stateId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      if (selectedVault == null) return false;
      if (accessToken == null) return false;
      if (mfilesUserId == null) return false;

      final url = Uri.parse('$baseUrl/api/WorkflowsInstance/SetObjectWorkflowstate');

      final body = {
        "vaultGuid": vaultGuidWithBraces,
        "objectTypeId": objectTypeId,
        "objectId": objectId,
        "stateId": stateId,
        "workflowId": workflowId,
        "userID": mfilesUserId,
      };

      // Debug logging
      if (kDebugMode) {
        debugPrint('🚀 SetObjectWorkflowstate URL: $url');
        debugPrint('📦 Body: ${jsonEncode(body)}');
      }

      final resp = await http.post(url, headers: _authHeaders, body: jsonEncode(body));

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) return true;

      _setError(resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}');
      //_setError('Server returned ${resp.statusCode}: ${resp.body}');

      if (kDebugMode) {
        debugPrint('📨 Status: ${resp.statusCode}');
        debugPrint('📨 Body: ${resp.body}');
      }

      return false;
    } catch (e) {
      _setError('Error setting workflow state: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // NEW: list workflows in vault
  Future<List<WorkflowOption>> fetchWorkflowsForObjectTypeClass({
    required int objectTypeId,
    required int classTypeId,
  }) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse(
      '$baseUrl/api/WorkflowsInstance/GetVaultsObjectClassTypeWorkflows/'
      '$vaultGuidWithBraces/$mfilesUserId/$objectTypeId/$classTypeId',
    );

    final resp = await http.get(url, headers: _authHeadersNoJson);

    if (resp.statusCode != 200) {
      throw Exception('GetVaultsObjectClassTypeWorkflows failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = json.decode(resp.body);
    if (decoded is! List) return <WorkflowOption>[];

    return decoded
        .whereType<Map<String, dynamic>>()
        .map(WorkflowOption.fromJson)
        .where((w) => w.id > 0 && w.title.trim().isNotEmpty)
        .toList();
  }

  //FETCHVAULTWORKFLOWS
   Future<List<WorkflowOption>> fetchVaultWorkflows() async {
       if (selectedVault == null || mfilesUserId == null || accessToken == null) {
         throw Exception('Session not ready');
       }

       final url = Uri.parse(
         '$baseUrl/api/WorkflowsInstance/GetVaultsWorkflows/$vaultGuidWithBraces/$mfilesUserId',
       );

       final resp = await http.get(url, headers: _authHeadersNoJson);

       if (resp.statusCode != 200) {
         throw Exception('GetVaultsWorkflows failed: ${resp.statusCode} ${resp.body}');
       }
       final decoded = json.decode(resp.body);
       if (decoded is! List) return <WorkflowOption>[];

       return decoded
           .whereType<Map<String, dynamic>>()
           .map(WorkflowOption.fromJson)
           .where((w) => w.id > 0 && w.title.trim().isNotEmpty)
           .toList();
   }

   //
   Future<WorkflowDefinition> fetchWorkflowDefinition(int workflowId) async {
      final url = Uri.parse(
        '$baseUrl/api/WorkflowsInstance/GetWorkflowDefinition/'
        '$vaultGuidWithBraces/$workflowId/$mfilesUserId',
      );

      final resp = await http.get(url, headers: _authHeadersNoJson);

      if (resp.statusCode != 200) {
        throw Exception('Failed to fetch workflow definition: ${resp.body}');
      }

      return WorkflowDefinition.fromJson(json.decode(resp.body));
    }

   // NEW: linked objects for an object
   Future<List<LinkedObjectsGroup>> fetchLinkedObjects({
    required String vaultGuid,
    required int objectTypeId,
    required int objectId,
    required int classId,
    required int userId,
    }) async {
      final uri = Uri.parse(
        '$baseUrl/api/objectinstance/LinkedObjects/$vaultGuid/$objectTypeId/$objectId/$classId/$userId',
      );

    final res = await http.get(uri, headers: _authHeadersNoJson);

      // ✅ No relationships is not an error
      if (res.statusCode == 404 || res.statusCode == 204) {
        return <LinkedObjectsGroup>[];
      }

      if (res.statusCode != 200) {
        throw Exception('LinkedObjects failed ${res.statusCode}: ${res.body}');
      }

      // some APIs return 200 with empty string
      if (res.body.trim().isEmpty) return <LinkedObjectsGroup>[];

      final decoded = jsonDecode(res.body);

      // handle either [] or { items: [] }
      final List list = decoded is List
          ? decoded
          : (decoded is Map && decoded['items'] is List)
              ? decoded['items'] as List
              : <dynamic>[];

      return list
          .whereType<Map<String, dynamic>>()
          .map(LinkedObjectsGroup.fromJson)
          .toList();
    }
  }



  //   // NEW: list workflows filtered for object type + class
  //   Future<List<WorkflowStateOption>> fetchWorkflowsForObjectTypeClass({
  //     required int objectTypeId,
  //     required int classTypeId,
  //   }) async {
  //     if (selectedVault == null || mfilesUserId == null || accessToken == null) {
  //       throw Exception('Session not ready');
  //     }

  //     final url = Uri.parse(
  //       '$baseUrl/api/WorkflowsInstance/GetVaultsObjectClassTypeWorkflows/'
  //       '${vaultGuidWithBraces}/$mfilesUserId/$objectTypeId/$classTypeId',
  //     );

  //     final resp = await http.get(url, headers: _authHeadersNoJson);

  //     if (resp.statusCode != 200) {
  //       throw Exception('GetVaultsObjectClassTypeWorkflows failed: ${resp.statusCode} ${resp.body}');
  //     }

  //     final decoded = json.decode(resp.body);
  //     if (decoded is! List) return <WorkflowStateOption>[];

  //     return decoded.whereType<Map<String, dynamic>>().map(WorkflowStateOption.fromJson).toList();
  //   }

  //   // NEW: get states for a workflow (use stateId=0 for initial choices)
  //     Future<List<WorkflowStateOption>> fetchWorkflowStates({
  //       required int workflowId,
  //       int stateId = 0,
  //     }) async {
  //       if (selectedVault == null || mfilesUserId == null || accessToken == null) {
  //         throw Exception('Session not ready');
  //       }

  //       final url = Uri.parse(
  //         '$baseUrl/api/WorkflowsInstance/GetObjectInWorkflowStates/'
  //         '${vaultGuidWithBraces}/$workflowId/$stateId/$mfilesUserId',
  //       );

  //       final resp = await http.get(url, headers: _authHeadersNoJson);

  //       if (resp.statusCode != 200) {
  //         throw Exception('GetObjectInWorkflowStates failed: ${resp.statusCode} ${resp.body}');
  //       }

  //       final decoded = json.decode(resp.body);
  //       if (decoded is! List) return <WorkflowStateOption>[];

  //       return decoded.whereType<Map<String, dynamic>>().map(WorkflowStateOption.fromJson).toList();
  //     }

  //     // NEW: semantic alias
  //     Future<bool> assignWorkflowToObject({
  //       required int objectTypeId,
  //       required int objectId,
  //       required int workflowId,
  //       required int initialStateId,
  //     }) async {
  //       return setObjectWorkflowState(
  //         objectTypeId: objectTypeId,
  //         objectId: objectId,
  //         workflowId: workflowId,
  //         stateId: initialStateId,
  //       );
  //     }


class WorkflowStateOption {
  final int id;
  final String title;

  WorkflowStateOption({required this.id, required this.title});

  factory WorkflowStateOption.fromJson(Map<String, dynamic> m) {
    return WorkflowStateOption(
      id: (m['id'] as num?)?.toInt() ?? 0,
      title: (m['title'] as String?) ?? '',
    );
  }
}

class WorkflowInfo {
  final String workflowTitle;
  final int workflowId;
  final int currentStateId;
  final String currentStateTitle;
  final String assignmentDesc;
  final List<WorkflowStateOption> nextStates;

  WorkflowInfo({
    required this.workflowTitle,
    required this.workflowId,
    required this.currentStateId,
    required this.currentStateTitle,
    required this.assignmentDesc,
    required this.nextStates,
  });

  factory WorkflowInfo.fromJson(Map<String, dynamic> m) {
    final next = (m['nextStates'] is List)
        ? (m['nextStates'] as List)
            .whereType<Map<String, dynamic>>()
            .map(WorkflowStateOption.fromJson)
            .toList()
        : <WorkflowStateOption>[];

    return WorkflowInfo(
      workflowTitle: (m['workflowTitle'] as String?) ?? '',
      workflowId: (m['workflowId'] as num?)?.toInt() ?? 0,
      currentStateId: (m['currentStateid'] as num?)?.toInt() ??
          (m['currentStateId'] as num?)?.toInt() ??
          0,
      currentStateTitle: (m['currentStateTitle'] as String?) ?? '',
      assignmentDesc: (m['assignmentdesc'] as String?) ?? '',
      nextStates: next,
    );
  }
}

class WorkflowOption {
  final int id;
  final String title;

  WorkflowOption({required this.id, required this.title});

  factory WorkflowOption.fromJson(Map<String, dynamic> m) {
    int _int(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? 0}') ?? 0;
    }

    String _str(dynamic v) => (v ?? '').toString();

    final id = _int(m['workflowId'] ?? m['id'] ?? m['workflowID']);
    final title = _str(m['workflowTitle'] ?? m['title'] ?? m['name'] ?? m['workflowName']);

    return WorkflowOption(id: id, title: title);
  }
}

class WorkflowDefinition {
  final int workflowId;
  final List<WorkflowStateOption> states;

  WorkflowDefinition({
    required this.workflowId,
    required this.states,
  });

  int get initialStateId => states.first.id;

  factory WorkflowDefinition.fromJson(Map<String, dynamic> m) {
    return WorkflowDefinition(
      workflowId: (m['workflowId'] as num).toInt(),
      states: (m['states'] as List)
          .map((s) => WorkflowStateOption(
                id: (s['stateId'] as num).toInt(),
                title: s['stateName'],
              ))
          .toList(),
    );
  }
}