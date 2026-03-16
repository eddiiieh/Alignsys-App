// ignore_for_file: curly_braces_in_flow_control_structures, avoid_print, unused_element

import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:mfiles_app/models/group_filter.dart';
import 'package:mfiles_app/models/linked_object_item.dart';
import 'package:mfiles_app/models/view_content_item.dart';
import 'package:mfiles_app/utils/file_icon_resolver.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/class_property.dart';
import '../models/lookup_item.dart';
import '../models/object_class.dart';
import '../models/object_comment.dart';
import '../models/object_creation_request.dart';
import '../models/object_file.dart';
import '../models/vault.dart';
import '../models/vault_object_type.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';

class MFilesService extends ChangeNotifier {
  // Auth
  String? accessToken;
  String? refreshToken;
  String? username;
  String? fullname;
  int? userId;
  int? mfilesUserId;

  // Vault
  Vault? selectedVault;
  List<Vault> vaults = [];

  // Object types and classes
  List<VaultObjectType> objectTypes = [];
  List<ObjectClass> objectClasses = [];
  final Map<int, ObjectClassesResponse> _classesByObjectType = {};

  // Class properties
  List<ClassProperty> classProperties = [];
  final Map<String, List<ClassProperty>> _classPropsCache = {};

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
  List<ViewObject> searchResults = [];

  String currentTab = 'Home';

  // Loading/Error
  bool isLoading = false;
  String? error;

  bool isAdmin = false;

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
      if (parts.length != 3) {
        print('❌ JWT has ${parts.length} parts, expected 3');
        return null;
      }

      final payload = parts[1];
      print('🔐 JWT payload (raw): ${payload.substring(0, 20)}...');

      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));

      print('🔐 JWT decoded: $decoded');

      final payloadMap = json.decode(decoded) as Map<String, dynamic>;

      final userId = payloadMap['user_id'] ??
          payloadMap['userId'] ??
          payloadMap['sub'] ??
          payloadMap['id'];

      print('🔐 Extracted userId: $userId (type: ${userId.runtimeType})');

      if (userId is int) return userId;
      if (userId is String) return int.tryParse(userId);
      if (userId is num) return userId.toInt();

      return null;
    } catch (e, stackTrace) {
      print('❌ JWT decode error: $e');
      print('   Stack: $stackTrace');
      return null;
    }
  }

  Future<void> saveTokens(
    String access,
    String refresh, {
    String? user,
    String? fullNameValue,
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
    if (fullNameValue != null) {
      await prefs.setString('full_name', fullNameValue);
      fullname = fullNameValue;
    }
    if (userIdValue != null) {
      await prefs.setInt('user_id', userIdValue);
      userId = userIdValue;
    }

    notifyListeners();
  }

  Future<bool> refreshAccessToken() async {
    if (refreshToken == null || refreshToken!.isEmpty) {
      print('❌ No refresh token available');
      return false;
    }

    try {
      print('🔄 Refreshing access token...');

      final response = await http.post(
        Uri.parse('https://auth.alignsys.tech/api/token/refresh/'),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode({'refresh': refreshToken}),
      );

      print('📡 Refresh response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newAccess = data['access'] as String?;

        if (newAccess != null && newAccess.isNotEmpty) {
          accessToken = newAccess;

          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('access_token', newAccess);

          if (userId == null) {
            userId = _decodeJwtAndGetUserId(newAccess);
            if (userId != null) {
              await prefs.setInt('user_id', userId!);
            }
          }

          print('✅ Access token refreshed successfully');
          notifyListeners();
          return true;
        }
      } else if (response.statusCode == 401) {
        print('❌ Refresh token expired - user needs to log in again');
        return false;
      }

      print('❌ Token refresh failed: ${response.statusCode}');
      return false;
    } catch (e) {
      print('❌ Token refresh error: $e');
      return false;
    }
  }

  Future<http.Response> _authenticatedRequest(
    Future<http.Response> Function() request, {
    bool retryOnAuthFailure = true,
  }) async {
    http.Response response = await request();

    if (response.statusCode == 401 && retryOnAuthFailure && refreshToken != null) {
      print('🔄 Got 401, attempting to refresh token...');

      final refreshed = await refreshAccessToken();

      if (refreshed) {
        print('♻️ Retrying original request with new token...');
        response = await request();
      } else {
        print('❌ Token refresh failed - logging out');
        await logout();
      }
    }

    return response;
  }

  Future<bool> tryAutoLogin() async {
    final prefs = await SharedPreferences.getInstance();
    final access = prefs.getString('access_token');
    final refresh = prefs.getString('refresh_token');

    if (access == null || access.isEmpty) return false;

    accessToken = access;
    refreshToken = refresh;
    username = prefs.getString('username');
    fullname = prefs.getString('full_name');
    userId = prefs.getInt('user_id') ?? _decodeJwtAndGetUserId(accessToken!);

    notifyListeners();
    return true;
  }

  Future<bool> loadTokens() async {
    final prefs = await SharedPreferences.getInstance();
    accessToken = prefs.getString('access_token');
    refreshToken = prefs.getString('refresh_token');
    username = prefs.getString('username');
    fullname = prefs.getString('full_name');
    userId = prefs.getInt('user_id');
    mfilesUserId = prefs.getInt('mfiles_user_id');

    print('📦 Loading tokens from SharedPreferences:');
    print('   accessToken: ${accessToken != null ? "present (${accessToken!.length} chars)" : "null"}');
    print('   refreshToken: ${refreshToken != null ? "present" : "null"}');
    print('   username: $username');
    print('   userId (from prefs): $userId');
    print('   mfilesUserId (from prefs): $mfilesUserId');

    if (userId == null && accessToken != null) {
      print('   Attempting to decode userId from JWT...');
      userId = _decodeJwtAndGetUserId(accessToken!);
      if (userId != null) {
        print('   ✅ Decoded userId from JWT: $userId');
        await prefs.setInt('user_id', userId!);
      } else {
        print('   ❌ Failed to decode userId from JWT');
      }
    }

    final hasTokens = accessToken != null && refreshToken != null;
    print('   Result: hasTokens = $hasTokens, userId = $userId');

    // ✅ Restore persisted relationship dots so they appear instantly on next launch
    _loadRelationshipsCacheFromPrefs(); // fire-and-forget

    return hasTokens;
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove('access_token');
    await prefs.remove('refresh_token');
    await prefs.remove('user_id');
    await prefs.remove('mfiles_user_id');
    await prefs.remove('username');
    await prefs.remove('full_name');
    await prefs.remove('selectedVaultGuid');
    await prefs.remove('vaultGuid');

    accessToken = null;
    refreshToken = null;
    userId = null;
    fullname = null;
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

    clearExtensionCache();
    clearClassPropertiesCache();
    clearRelationshipsCache();

    isAdmin = false;

    notifyListeners();
  }

  Future<bool> login(String email, String password) async {
    final body = {'username': email, 'password': password, 'auth_type': 'email'};

    print('🔐 Attempting login for: $email');

    final response = await http.post(
      Uri.parse('https://auth.alignsys.tech/api/token/'),
      headers: const {'Content-Type': 'application/json'},
      body: json.encode(body),
    );

    print('📡 Login response status: ${response.statusCode}');

    if (response.statusCode != 200) {
      throw Exception('Login failed: ${response.statusCode}');
    }

    final data = json.decode(response.body);
    print('📡 Login response body: $data');

    final access = data['access'] as String?;
    final refresh = data['refresh'] as String?;
    final name = (data['full_name'] ?? data['name'] ?? data['fullName'] ?? '').toString();

    if (access == null || access.isEmpty || refresh == null || refresh.isEmpty) {
      throw Exception('Login failed: token missing in response');
    }

    accessToken = access;
    refreshToken = refresh;

    userId = _decodeJwtAndGetUserId(accessToken!);
    print('🔐 Decoded userId from login token: $userId');

    if (userId == null) {
      print('⚠️ Warning: Could not decode userId from JWT token');
    }

    await saveTokens(
      accessToken!,
      refreshToken!,
      user: email,
      fullNameValue: name.isNotEmpty ? name : null,
      userIdValue: userId,
    );

    print('✅ Login successful, tokens saved');
    return true;
  }

  Future<void> requestPasswordReset(String email) async {
    final response = await http.post(
      Uri.parse('https://auth.alignsys.tech/api/password_reset/'),
      headers: const {'Content-Type': 'application/x-www-form-urlencoded'},
      body: 'email=${Uri.encodeComponent(email)}',
    );

    if (response.statusCode != 200 &&
        response.statusCode != 201 &&
        response.statusCode != 204) {
      throw Exception('Password reset failed: ${response.statusCode} — ${response.body}');
    }
  }

  Future<List<Vault>> getUserVaults() async {
    if (accessToken == null) throw Exception("User not logged in");

    late http.Response response;
    try {
      response = await _authenticatedRequest(
        () => http.get(
          Uri.parse('https://auth.alignsys.tech/api/user/vaults/'),
          headers: {
            'Authorization': 'Bearer $accessToken',
            'Content-Type': 'application/json',
          },
        ),
      );
    } catch (e) {
      throw Exception('Failed to fetch vaults: $e');
    }

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;
      vaults = data.map((v) => Vault.fromJson(v)).toList();
      notifyListeners();
      return vaults;
    }

    throw Exception('Failed to fetch vaults: ${response.statusCode}');
  }

  Future<void> fetchMFilesUserId() async {
    print('🔍 fetchMFilesUserId called');
    print('   selectedVault: ${selectedVault?.guid}');
    print('   accessToken: ${accessToken != null ? "present" : "null"}');
    print('   userId: $userId');
    print('   mfilesUserId (cached): $mfilesUserId');

    if (mfilesUserId != null) {
      print('   ✅ Using cached mfilesUserId: $mfilesUserId');
      return;
    }

    if (selectedVault == null) {
      print('❌ No vault selected');
      _setError('No vault selected');
      return;
    }

    if (accessToken == null) {
      print('❌ No access token');
      _setError('Not authenticated');
      return;
    }

    try {
      final url = '$baseUrl/api/user/mfiles-profile/$vaultGuidNoBraces';
      print('🌐 Fetching: $url');

      final response = await _authenticatedRequest(
        () => http.get(Uri.parse(url), headers: _authHeadersNoJson),
      );

      print('📡 Response status: ${response.statusCode}');
      print('📡 Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        debugPrint('🔐 mfiles-profile response: $data');
        mfilesUserId = (data['id'] as num?)?.toInt();
        isAdmin = data['isAdmin'] as bool? ?? false;
        debugPrint('✅ isAdmin set to: $isAdmin');

        print('✅ mfilesUserId set to: $mfilesUserId');

        final prefs = await SharedPreferences.getInstance();
        if (mfilesUserId != null) {
          await prefs.setInt('mfiles_user_id', mfilesUserId!);
        }

        notifyListeners();
        return;
      }

      if (response.statusCode == 404) {
        print('⚠️ User profile not found (404), using fallback mapping');
      } else {
        print('⚠️ Non-200 status (${response.statusCode}), using fallback mapping');
      }

      await _useFallbackMapping();
    } catch (e, stackTrace) {
      print('❌ Exception in fetchMFilesUserId: $e');
      print('   Stack: $stackTrace');
      await _useFallbackMapping();
    }
  }

  Future<void> _useFallbackMapping() async {
    print('🔄 Using fallback mapping');
    print('   userId before: $userId');

    if (userId == null) {
      if (accessToken != null) {
        print('   Attempting emergency JWT decode...');
        userId = _decodeJwtAndGetUserId(accessToken!);
        print('   Emergency decode result: $userId');

        if (userId != null) {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setInt('user_id', userId!);
        }
      }
    }

    if (userId == null) {
      print('❌ userId is still null, cannot use fallback');
      _setError('M-Files user not resolved');
      return;
    }

    mfilesUserId = (userId == 37) ? 20 : userId;
    print('✅ mfilesUserId set to (fallback): $mfilesUserId');
    isAdmin = false;
    debugPrint('⚠️ Fallback used — isAdmin defaulting to false');

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

    final cacheKey = '$objectTypeId-$classId';

    if (_classPropsCache.containsKey(cacheKey)) {
      classProperties = _classPropsCache[cacheKey]!;
      if (kDebugMode) {
        debugPrint('📦 Using cached class properties for $cacheKey (${classProperties.length} props)');
      }
      return;
    }

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/MfilesObjects/ClassProps/$vaultGuidWithBraces/$objectTypeId/$classId/$mfilesUserId',
      );

      final response = await http.get(url, headers: _authHeadersNoJson);

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        final props = data.map((e) => ClassProperty.fromJson(e)).toList();

        classProperties = props;
        _classPropsCache[cacheKey] = props;

        if (kDebugMode) {
          debugPrint('✅ Fetched and cached class properties for $cacheKey (${props.length} props)');
        }
      } else {
        _setError('Failed to fetch class properties: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching class properties: $e');
    } finally {
      _setLoading(false);
    }
  }

  void clearClassPropertiesCache() {
    _classPropsCache.clear();
    if (kDebugMode) {
      debugPrint('🧹 Cleared class properties cache');
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
        warmExtensionsForObjects(searchResults);
        warmRelationshipsForObjects(searchResults);
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
      if (accessToken == null) throw Exception('Not logged in');
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
    if (accessToken == null) {
      _setError('Not logged in (missing accessToken)');
      return;
    }
    if (selectedVault == null) {
      _setError('No vault selected');
      return;
    }
    if (mfilesUserId == null) {
      _setError('M-Files user not resolved');
      return;
    }

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse('$baseUrl/api/Views/GetViews/$vaultGuidWithBraces/$mfilesUserId');

      final response = await _authenticatedRequest(
        () => http.get(url, headers: _authHeadersNoJson),
      );

      if (kDebugMode) {
        debugPrint('VIEWS status=${response.statusCode}');
        debugPrint('VIEWS body=${response.body}');
      }

      if (response.statusCode == 200) {
        final decoded = json.decode(response.body);

        if (decoded is Map<String, dynamic>) {
          final common = (decoded['commonViews'] ?? decoded['CommonViews'] ?? decoded['common_views']) as List? ?? [];
          final other = (decoded['otherViews'] ?? decoded['OtherViews'] ?? decoded['other_views']) as List? ?? [];

          commonViews = common.map((e) => ViewItem.fromJson(e)).toList();
          otherViews = other.map((e) => ViewItem.fromJson(e)).toList();
          allViews = [...commonViews, ...otherViews];
          notifyListeners();
        } else {
          _setError('Unexpected views response shape: ${decoded.runtimeType}');
        }
      } else {
        _setError('Failed to fetch views: ${response.statusCode} ${response.body}');
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

      final response = await _authenticatedRequest(
        () => http.get(url, headers: _authHeadersNoJson),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        final fetched = data.map((e) => ViewObject.fromJson(e as Map<String, dynamic>)).toList();

        fetched.sort((a, b) {
          final ad = a.lastModifiedUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
          final bd = b.lastModifiedUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
          return bd.compareTo(ad);
        });

        recentObjects = fetched;
        warmExtensionsForObjects(recentObjects);
        warmRelationshipsForObjects(recentObjects);
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

      final response = await _authenticatedRequest(
        () => http.get(url, headers: _authHeadersNoJson),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        assignedObjects = data
            .whereType<Map<String, dynamic>>()
            .map((e) => ViewObject.fromJson(e))
            .toList();

        warmExtensionsForObjects(assignedObjects);
        warmRelationshipsForObjects(assignedObjects);
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
    if (decoded is Map && decoded['props'] is List) {
      return (decoded['props'] as List).cast<Map<String, dynamic>>();
    }
    if (decoded is Map && decoded['properties'] is List) {
      return (decoded['properties'] as List).cast<Map<String, dynamic>>();
    }

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

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
        return true;
      }

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

    final resp = await _authenticatedRequest(
      () => http.get(url, headers: _authHeadersNoJson),
    );

    if (resp.statusCode == 404) return <ObjectFile>[];

    if (resp.statusCode != 200) {
      throw Exception('GetObjectFiles failed: ${resp.statusCode} ${resp.body}');
    }

    final data = json.decode(resp.body) as List;
    return data
        .whereType<Map<String, dynamic>>()
        .map((e) => ObjectFile.fromJson(e))
        .toList();
  }

  // ==================== FILE EXTENSION CACHE (for icons) ====================

  final Map<int, String> _extByObjectId = {};
  final Set<int> _extInFlight = {};

  String? cachedExtensionForObject(int objectId) => _extByObjectId[objectId];

  String _normalizeExt(String? ext) {
    final e = (ext ?? '').trim().toLowerCase();
    if (e.isEmpty) return '';
    return e.startsWith('.') ? e.substring(1) : e;
  }

  Future<void> ensureExtensionForObject({
    required int objectId,
    required int classId,
  }) async {
    if (objectId <= 0) return;

    if (_extByObjectId.containsKey(objectId)) return;
    if (_extInFlight.contains(objectId)) return;

    _extInFlight.add(objectId);
    try {
      final files = await fetchObjectFiles(objectId: objectId, classId: classId);
      final ext = files.isNotEmpty ? _normalizeExt(files.first.extension) : '';
      _extByObjectId[objectId] = ext;
      notifyListeners();
    } catch (_) {
      _extByObjectId[objectId] = '';
      notifyListeners();
    } finally {
      _extInFlight.remove(objectId);
    }
  }

  void warmExtensionsForItems(List<ViewContentItem> items) {
  for (final it in items) {
    if (!it.isObject) continue;
    if (it.id <= 0) continue;
    if (isMultiFile(objectTypeId: it.objectTypeId, isSingleFile: it.isSingleFile)) continue;
    ensureExtensionForObject(objectId: it.id, classId: it.classId);
  }
}

  void warmExtensionsForObjects(List<ViewObject> objects) {
    for (final o in objects) {
      if (o.id <= 0) continue;
      // Multifiles don't resolve to a single extension
      if (isMultiFile(objectTypeId: o.objectTypeId, isSingleFile: o.isSingleFile)) continue;
      ensureExtensionForObject(objectId: o.id, classId: o.classId);
    }
  }

  void clearExtensionCache() {
    _extByObjectId.clear();
    _extInFlight.clear();
  }

  // ==================== RELATIONSHIPS PRESENCE CACHE ====================

  // objectId -> true (has relationships) / false (none confirmed)
  final Map<int, bool> _hasRelationshipsCache = {};
  final Set<int> _relInFlight = {};

  // Max concurrent LinkedObjects requests per batch chunk
  static const int _relConcurrency = 4;

  /// Returns cached relationships presence:
  /// - `true`  → confirmed has at least one relationship → show blue dot
  /// - `false` → confirmed empty → no dot
  /// - `null`  → not yet checked → no dot yet
  bool? cachedHasRelationships(int objectId) => _hasRelationshipsCache[objectId];

  // ── Persistence: store/restore dots across app launches ──────────────────

  Future<void> _loadRelationshipsCacheFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('rel_')).toList();
      for (final key in keys) {
        final id = int.tryParse(key.substring(4));
        if (id != null) {
          _hasRelationshipsCache[id] = prefs.getBool(key) ?? false;
        }
      }
      if (_hasRelationshipsCache.isNotEmpty) {
        notifyListeners(); // dots appear immediately on launch
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to load relationships cache from prefs: $e');
    }
  }

  void _saveRelationshipToPrefs(int objectId, bool hasRel) {
    // Fire-and-forget — never blocks the UI
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('rel_$objectId', hasRel);
    }).catchError((_) {});
  }

  Future<void> _clearRelationshipsCacheFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((k) => k.startsWith('rel_')).toList();
      for (final key in keys) {
        await prefs.remove(key);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('⚠️ Failed to clear relationships cache from prefs: $e');
    }
  }

  // ── Single-object fetch (called when user taps chevron manually) ──────────

  Future<void> ensureRelationshipsPresenceForObject({
    required int objectId,
    required int objectTypeId,
    required int classId,
  }) async {
    if (objectId <= 0 || objectTypeId <= 0 || classId <= 0) return;
    if (_hasRelationshipsCache.containsKey(objectId)) return;
    if (_relInFlight.contains(objectId)) return;

    _relInFlight.add(objectId);
    try {
      final groups = await fetchLinkedObjects(
        vaultGuid: vaultGuidWithBraces,
        objectTypeId: objectTypeId,
        objectId: objectId,
        classId: classId,
        userId: currentUserId,
      );
      final hasRel = groups.any((g) => g.items.isNotEmpty);
      _hasRelationshipsCache[objectId] = hasRel;
      _saveRelationshipToPrefs(objectId, hasRel);
      notifyListeners();
    } catch (_) {
      // Don't cache errors — allow a retry on next interaction
    } finally {
      _relInFlight.remove(objectId);
    }
  }

  // ── Batch warm: fires _relConcurrency requests simultaneously, ────────────
  // ── notifies once per chunk so dots appear progressively ─────────────────

  Future<void> _warmRelationshipsBatch(
    List<({int objectId, int objectTypeId, int classId})> items,
  ) async {
    // Only process items not already cached or in-flight
    final todo = items.where((it) =>
      it.objectId > 0 &&
      it.objectTypeId > 0 &&
      it.classId > 0 &&
      !_hasRelationshipsCache.containsKey(it.objectId) &&
      !_relInFlight.contains(it.objectId),
    ).toList();

    if (todo.isEmpty) return;

    // Mark all in-flight immediately to block duplicate calls from other paths
    for (final it in todo) _relInFlight.add(it.objectId);

    for (int i = 0; i < todo.length; i += _relConcurrency) {
      final chunk = todo.skip(i).take(_relConcurrency).toList();

      // Fire chunk concurrently, collect results
      final results = await Future.wait(
        chunk.map((it) async {
          try {
            final groups = await fetchLinkedObjects(
              vaultGuid: vaultGuidWithBraces,
              objectTypeId: it.objectTypeId,
              objectId: it.objectId,
              classId: it.classId,
              userId: currentUserId,
            );
            return (id: it.objectId, hasRel: groups.any((g) => g.items.isNotEmpty));
          } catch (_) {
            return (id: it.objectId, hasRel: false);
          }
        }),
      );

      // Write results and persist
      for (final r in results) {
        _hasRelationshipsCache[r.id] = r.hasRel;
        _relInFlight.remove(r.id);
        _saveRelationshipToPrefs(r.id, r.hasRel);
      }

      // Single notify per chunk — dots appear progressively every 4 objects
      notifyListeners();
    }
  }

  void warmRelationshipsForObjects(List<ViewObject> objects) {
    final items = objects
        .where((o) =>
            o.id > 0 &&
            o.objectTypeId > 0 &&
            o.classId > 0 &&
            !isDocumentViewObject(o))
        .map((o) => (
              objectId: o.id,
              objectTypeId: o.objectTypeId,
              classId: o.classId,
            ))
        .toList();
    _warmRelationshipsBatch(items); // intentionally not awaited
  }

  void warmRelationshipsForItems(List<ViewContentItem> items) {
    final batch = items
        .where((it) =>
            it.isObject &&
            it.id > 0 &&
            it.objectTypeId > 0 &&
            it.classId > 0 &&
            !isDocumentContentItem(it))
        .map((it) => (
              objectId: it.id,
              objectTypeId: it.objectTypeId,
              classId: it.classId,
            ))
        .toList();
    _warmRelationshipsBatch(batch); // intentionally not awaited
  }

  void clearRelationshipsCache() {
    _hasRelationshipsCache.clear();
    _relInFlight.clear();
    _clearRelationshipsCacheFromPrefs(); // fire-and-forget
    if (kDebugMode) debugPrint('🧹 Cleared relationships presence cache');
  }

  // ==================== DOWNLOAD / BASE64 FLEX ====================

  Object? _pickAnyKeyCI(Map m, String key) {
    final target = key.trim().toLowerCase();
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

  String? _deepFindBase64(dynamic node) {
    if (node is String) {
      final s = node.trim();
      final looks = s.length > 100 && RegExp(r'^[A-Za-z0-9+/=\s]+$').hasMatch(s);
      return looks ? s : null;
    }
    if (node is List) {
      for (final x in node) {
        final found = _deepFindBase64(x);
        if (found != null) return found;
      }
    }
    if (node is Map) {
      for (final e in node.entries) {
        if (e.key is String && (e.key as String).trim().toLowerCase() == 'base64') {
          final found = _deepFindBase64(e.value);
          if (found != null) return found;
        }
      }
      for (final e in node.entries) {
        final found = _deepFindBase64(e.value);
        if (found != null) return found;
      }
    }
    return null;
  }

  bool _looksLikeJson(List<int> bytes) {
    int i = 0;
    while (i < bytes.length) {
      final b = bytes[i];
      if (b == 0x20 || b == 0x0A || b == 0x0D || b == 0x09) {
        i++;
        continue;
      }
      return b == 0x7B || b == 0x5B;
    }
    return false;
  }

  Future<({List<int> bytes, String? contentType})> downloadFileBytesWithFallback({
    required int displayObjectId,
    required int classId,
    required int fileId,
    required String reportGuid,
    required String expectedExtension,
  }) async {
    if (selectedVault == null || accessToken == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse('$baseUrl/api/objectinstance/DownloadOtherFiles').replace(
      queryParameters: {
        'ObjectId': displayObjectId.toString(),
        'VaultGuid': vaultGuidWithBraces,
        'fileID': fileId.toString(),
        'ClassId': classId.toString(),
      },
    );

    debugPrint('📥 Downloading file from: $url');

    try {
      final response = await http.get(url, headers: _authHeadersNoJson);

      debugPrint('📡 Response status: ${response.statusCode}');
      debugPrint('📡 Content-Type: ${response.headers['content-type']}');
      debugPrint('📡 Content-Length: ${response.headers['content-length']}');

      if (response.statusCode == 200) {
        final contentType = response.headers['content-type'];
        final bytes = response.bodyBytes;

        String headAscii(List<int> b) {
          final take = b.length > 32 ? b.sublist(0, 32) : b;
          return String.fromCharCodes(take.map((x) => (x >= 32 && x <= 126) ? x : 46));
        }

        bool looksPdf(List<int> b) =>
            b.length >= 4 && b[0] == 0x25 && b[1] == 0x50 && b[2] == 0x44 && b[3] == 0x46;

        bool looksZip(List<int> b) => b.length >= 2 && b[0] == 0x50 && b[1] == 0x4B;

        debugPrint('🔎 HEAD(ASCII): ${headAscii(bytes)}');

        bool looksJson(List<int> b) {
          int i = 0;
          while (i < b.length) {
            final x = b[i];
            if (x == 0x20 || x == 0x0A || x == 0x0D || x == 0x09) {
              i++;
              continue;
            }
            return x == 0x7B || x == 0x5B;
          }
          return false;
        }

        final head = headAscii(bytes).toLowerCase();

        if (looksJson(bytes)) {
          final body = utf8.decode(bytes);
          throw Exception(
            'Server returned JSON instead of file. '
            'HEAD=${headAscii(bytes)} '
            'BODY=${body.substring(0, body.length > 200 ? 200 : body.length)}',
          );
        }

        if (head.contains('<!doctype') || head.contains('<html')) {
          throw Exception('Server returned HTML instead of file. HEAD=${headAscii(bytes)}');
        }

        final exp = expectedExtension.trim().toLowerCase().replaceFirst('.', '');

        if (contentType?.contains('text') == true) {
          final body = utf8.decode(bytes);
          if (body.contains('not been committed')) {
            throw Exception('File not committed. Please check in the file in M-Files first.');
          }
          if (body.contains('Could not find')) {
            throw Exception('File signature error. File may be corrupted.');
          }
          throw Exception('Server error: ${body.substring(0, body.length > 200 ? 200 : body.length)}');
        }

        if (exp == 'pdf' && !looksPdf(bytes)) {
          throw Exception('Expected PDF but downloaded content is not PDF. HEAD=${headAscii(bytes)}');
        }
        if (['docx', 'xlsx', 'pptx'].contains(exp) && !looksZip(bytes)) {
          throw Exception('Expected Office zip ($exp) but downloaded content is not ZIP. HEAD=${headAscii(bytes)}');
        }

        debugPrint('🔎 looksPdf=${looksPdf(bytes)} looksZip=${looksZip(bytes)} bytes=${bytes.length}');
        debugPrint('✅ Downloaded ${bytes.length} bytes');

        return (bytes: bytes, contentType: contentType);
      }

      throw Exception('Download failed: ${response.statusCode}');
    } catch (e) {
      debugPrint('❌ Download error: $e');
      rethrow;
    }
  }

  String _safeFilename(String title, String extension, int fileId) {
    final ext = extension.trim().toLowerCase().replaceFirst('.', '');
    var base = title.trim().isEmpty ? 'file_$fileId' : title.trim();
    base = base.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    if (ext.isEmpty) return base;
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
      expectedExtension: extension,
    );

    final filename = _safeFilename(fileTitle, extension, fileId);
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';

    final file = File(filePath);
    await file.writeAsBytes(result.bytes, flush: true);

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
      expectedExtension: extension,
    );

    final filename = _safeFilename(fileTitle, extension, fileId);
    final dir = await getApplicationDocumentsDirectory();
    final path = '${dir.path}/$filename';

    final out = File(path);
    await out.writeAsBytes(result.bytes, flush: true);

    return path;
  }

  // ==================== CONVERT TO PDF ====================

  Future<Map<String, dynamic>> convertToPdf({
    required int objectId,
    required int classId,
    required int fileId,
    bool overWriteOriginal = false,
    bool separateFile = true,
  }) async {
    if (selectedVault == null || accessToken == null || mfilesUserId == null) {
      throw Exception('Session not ready');
    }

    final url = Uri.parse('$baseUrl/api/objectinstance/ConvertToPdf');

    final body = {
      "vaultGuid": vaultGuidWithBraces,
      "objectId": objectId,
      "classId": classId,
      "fileID": fileId,
      "overWriteOriginal": overWriteOriginal,
      "separateFile": separateFile,
      "userID": mfilesUserId,
    };

    final resp = await http.post(url, headers: _authHeaders, body: jsonEncode(body));

    if (resp.statusCode != 200 && resp.statusCode != 201) {
      throw Exception('ConvertToPdf failed: ${resp.statusCode} ${resp.body}');
    }

    final decoded = jsonDecode(resp.body);
    if (decoded is Map<String, dynamic>) return decoded;

    throw Exception('ConvertToPdf unexpected response: ${resp.body}');
  }

  int extractPdfFileId(Map<String, dynamic> m) {
    int? asInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      return int.tryParse('${v ?? ''}');
    }

    final candidates = [
      m['pdfFileId'],
      m['PdfFileId'],
      m['newFileId'],
      m['fileId'],
      m['fileID'],
      m['convertedFileId'],
      m['ConvertedFileId'],
      (m['data'] is Map ? (m['data'] as Map)['fileId'] : null),
      (m['result'] is Map ? (m['result'] as Map)['fileId'] : null),
    ];

    for (final c in candidates) {
      final id = asInt(c);
      if (id != null && id > 0) return id;
    }

    throw Exception('Could not find pdf fileId in ConvertToPdf response. Keys=${m.keys.toList()}');
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

        warmExtensionsForObjects(deletedObjects);
        warmRelationshipsForObjects(deletedObjects);
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
    warmExtensionsForObjects(reportObjects);
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

    debugPrint("VIEW FETCH URL: $url");

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

    final items = list.whereType<Map<String, dynamic>>().map(ViewContentItem.fromJson).toList();

    warmExtensionsForItems(items);
    warmRelationshipsForItems(items);

    return items;
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

    final items = decoded.whereType<Map<String, dynamic>>().map(ViewContentItem.fromJson).toList();
    warmRelationshipsForItems(items);
    return items;
  }

  // -------------------- Comments --------------------

  Future<List<ObjectComment>> fetchComments({
    required int objectId,
    required int objectTypeId,
    required String vaultGuid,
  }) async {
    error = null;

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

    return data.whereType<Map<String, dynamic>>().map(ObjectComment.fromJson).toList();
  }

  Future<bool> postComment({
    required String comment,
    required int objectId,
    required int objectTypeId,
    required String vaultGuid,
  }) async {
    error = null;

    final uri = Uri.parse('$baseUrl/api/Comments');

    final displayName = (fullname?.trim().isNotEmpty == true ? fullname! : username ?? '').trim();
    final prefixedComment = displayName.isNotEmpty ? '$displayName : $comment' : comment;

    final payload = {
      "comment": prefixedComment,
      "objectId": objectId,
      "vaultGuid": vaultGuid,
      "objectTypeId": objectTypeId,
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

  // -------------------- Delete & Undelete object --------------------

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

  Future<bool> unDeleteObject({
    required int objectId,
    required int classId,
  }) async {
    _setLoading(true);
    _setError(null);

    try {
      if (selectedVault == null) return false;
      if (accessToken == null) return false;
      if (mfilesUserId == null) return false;

      final url = Uri.parse('$baseUrl/api/ObjectDeletion/UnDeleteObject');

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
      _setError('Error restoring object: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // ==================== WORKFLOWS ====================

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

      if (kDebugMode) {
        debugPrint('🚀 SetObjectWorkflowstate URL: $url');
        debugPrint('📦 Body: ${jsonEncode(body)}');
      }

      final resp = await http.post(url, headers: _authHeaders, body: jsonEncode(body));

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) return true;

      _setError(resp.body.isNotEmpty ? resp.body : 'HTTP ${resp.statusCode}');

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

    if (res.statusCode == 404 || res.statusCode == 204) {
      return <LinkedObjectsGroup>[];
    }

    if (res.statusCode != 200) {
      throw Exception('LinkedObjects failed ${res.statusCode}: ${res.body}');
    }

    if (res.body.trim().isEmpty) return <LinkedObjectsGroup>[];

    final decoded = jsonDecode(res.body);

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

  bool isMultiFile({required int objectTypeId, required bool isSingleFile}) {
    return objectTypeId == 0 && !isSingleFile;
  }

  // ==================== ICON RESOLUTION ====================

  bool isDocumentObjectType(int objectTypeId) {
    final t = objectTypes.firstWhere(
      (x) => x.id == objectTypeId,
      orElse: () => VaultObjectType(id: 0, displayName: '', isDocument: false, name: ''),
    );
    return t.isDocument;
  }

  bool isDocumentViewObject(ViewObject obj) {
    if (isMultiFile(objectTypeId: obj.objectTypeId, isSingleFile: obj.isSingleFile)) {
      return false;
    }
    return isDocumentObjectType(obj.objectTypeId);
  }

  bool isDocumentContentItem(ViewContentItem item) {
    if (!item.isObject) return false;
    if (isMultiFile(objectTypeId: item.objectTypeId, isSingleFile: item.isSingleFile)) {
      return false;
    }
    return isDocumentObjectType(item.objectTypeId);
  }

  IconData iconForViewObject(ViewObject obj) {
    if (!isDocumentViewObject(obj)) return FileIconResolver.nonDocumentIcon;

    final ext = cachedExtensionForObject(obj.id);
    if (ext != null && ext.trim().isNotEmpty) {
      return FileIconResolver.iconForExtension(ext);
    }
    return FileIconResolver.unknownIcon;
  }

  IconData iconForContentItem(ViewContentItem item) {
    if (!item.isObject) return FileIconResolver.nonDocumentIcon;
    if (!isDocumentContentItem(item)) return FileIconResolver.nonDocumentIcon;

    final ext = cachedExtensionForObject(item.id);
    if (ext != null && ext.trim().isNotEmpty) {
      return FileIconResolver.iconForExtension(ext);
    }
    return FileIconResolver.unknownIcon;
  }

  // ==================== VAULT SELECTION PERSISTENCE ====================

  Future<void> saveSelectedVault(Vault v) async {
    selectedVault = v;
    final prefs = await SharedPreferences.getInstance();

    await prefs.setString('selectedVaultGuid', v.guid);
    await prefs.setString('selectedVaultName', v.name);
    await prefs.setString('selectedVaultId', v.vaultId);

    mfilesUserId = null;
    await prefs.remove('mfiles_user_id');

    clearClassPropertiesCache();
    clearExtensionCache();
    clearRelationshipsCache();

    notifyListeners();
  }

  Future<void> restoreSelectedVault() async {
    final prefs = await SharedPreferences.getInstance();
    final guid = prefs.getString('selectedVaultGuid');
    final name = prefs.getString('selectedVaultName');
    final vaultId = prefs.getString('selectedVaultId');

    print('🔄 Restoring vault from SharedPreferences:');
    print('   guid: $guid');
    print('   name: $name');
    print('   vaultId: $vaultId');

    if (guid != null && guid.isNotEmpty) {
      selectedVault = Vault(
        vaultId: vaultId ?? guid,
        guid: guid,
        name: name ?? 'Vault',
      );
      print('   ✅ Vault restored successfully');
      notifyListeners();
    } else {
      print('   ⚠️ No vault found in SharedPreferences');
    }
  }

  // ==================== ASSIGNMENTS ====================

  /// Approves or un-approves an assignment for a specific user.
  ///
  /// Maps to: POST /api/objectinstance/ApproveAssignment
  ///
  /// Only the user whose [userId] matches the logged-in M-Files user should
  /// call this. The [approve] flag mirrors the web client's toggle:
  ///   - `true`  → mark this user's approval as complete
  ///   - `false` → withdraw this user's approval
  Future<bool> approveAssignment({
    required int objectId,
    required int classId,
    required int userId,
    required bool approve,
  }) async {
    if (selectedVault == null || accessToken == null || mfilesUserId == null) {
      _setError('Session not ready');
      return false;
    }

    // ── Enforce: only the current logged-in user may approve/withdraw ──
    if (userId != mfilesUserId) {
      _setError('You can only approve assignments assigned to you.');
      return false;
    }

    try {
      final url = Uri.parse('$baseUrl/api/objectinstance/ApproveAssignment');

      final body = {
        "vaultGuid": vaultGuidWithBraces,
        "objectId": objectId,
        "classId": classId,
        "userID": userId,
        "approve": approve,
      };

      if (kDebugMode) {
        debugPrint('🚀 ApproveAssignment URL: $url');
        debugPrint('📦 Body: ${jsonEncode(body)}');
      }

      final resp = await _authenticatedRequest(
        () => http.post(url, headers: _authHeaders, body: jsonEncode(body)),
      );

      if (kDebugMode) {
        debugPrint('📨 ApproveAssignment status: ${resp.statusCode}');
        debugPrint('📨 ApproveAssignment body: ${resp.body}');
      }

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
        // If the approval is being set to true, remove from the assigned list
        // so the home screen updates without a full refresh.
        if (approve) {
          assignedObjects.removeWhere((o) => o.id == objectId);
          notifyListeners();
        }
        return true;
      }

      _setError('ApproveAssignment failed: ${resp.statusCode} ${resp.body}');
      return false;
    } catch (e) {
      _setError('Error approving assignment: $e');
      return false;
    }
  }

  /// Legacy method kept for backward compatibility.
  /// Prefer [approveAssignment] for assignment objects.
  Future<bool> markAssignmentComplete({
    required int objectId,
    required int classId,
  }) async {
    if (selectedVault == null || accessToken == null || mfilesUserId == null) {
      return false;
    }

    try {
      final url = Uri.parse('$baseUrl/api/Assignment/CompleteAssignment');

      final body = {
        "vaultGuid": vaultGuidWithBraces,
        "objectId": objectId,
        "classId": classId,
        "userID": mfilesUserId,
      };

      final resp = await _authenticatedRequest(
        () => http.post(url, headers: _authHeaders, body: jsonEncode(body)),
      );

      if (resp.statusCode == 200 || resp.statusCode == 201 || resp.statusCode == 204) {
        assignedObjects.removeWhere((o) => o.id == objectId);
        notifyListeners();
        return true;
      }

      _setError('Complete assignment failed: ${resp.statusCode} ${resp.body}');
      return false;
    } catch (e) {
      _setError('Error completing assignment: $e');
      return false;
    }
  }
}

// ==================== MODELS (kept outside service) ====================

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
  final bool isAssignedToMe;

  WorkflowInfo({
    required this.workflowTitle,
    required this.workflowId,
    required this.currentStateId,
    required this.currentStateTitle,
    required this.assignmentDesc,
    required this.nextStates,
    this.isAssignedToMe = false,
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
      isAssignedToMe: (m['isAssignedToMe'] as bool?) ??
          (m['assignedToCurrentUser'] as bool?) ??
          (m['isAssignedToCurrentUser'] as bool?) ??
          false,
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