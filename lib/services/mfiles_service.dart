import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mfiles_app/models/view_content_item.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vault_object_type.dart';
import '../models/object_class.dart';
import '../models/class_property.dart';
import '../models/lookup_item.dart';
import '../models/object_creation_request.dart';
import '../models/vault.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';

class MFilesService extends ChangeNotifier {
  // Auth
  String? accessToken;
  String? refreshToken;
  String? username;
  int? userId; // Auth system user ID (37)
  int? mfilesUserId; // M-Files user ID (20) - ADD THIS

  // Vault
  Vault? selectedVault;
  List<Vault> vaults = [];

  /// Returns the GUID of the currently selected vault
  String get vaultGuid {
    if (selectedVault == null) {
      throw Exception('No vault selected');
    }
    // Remove curly braces from GUID - M-Files often rejects them
  return selectedVault!.guid;
  }

  /// Returns the M-Files user ID (not auth user ID)
  int get currentUserId {
    if (mfilesUserId == null) {
      throw Exception('M-Files User ID is not set');
    }
    return mfilesUserId!;
  }

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

  void clearError() {
    _setError(null);
  }

  // JWT decoding helper
  int? _decodeJwtAndGetUserId(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      String normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final payloadMap = json.decode(decoded) as Map<String, dynamic>;
      return payloadMap['user_id'] as int?;
    } catch (_) {
      return null;
    }
  }

  // Token storage
  Future<void> saveTokens(String access, String refresh, {String? user, int? userIdValue}) async {
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
    mfilesUserId = prefs.getInt('mfiles_user_id'); // Load M-Files user ID

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
    await prefs.remove('mfiles_user_id'); // Clear M-Files user ID

    accessToken = null;
    refreshToken = null;
    userId = null;
    mfilesUserId = null;
    selectedVault = null;
    vaults.clear();
    objectTypes.clear();
    objectClasses.clear();
    _classesByObjectType.clear();
  }

  // LOGIN
  Future<bool> login(String email, String password) async {
    try {
      final body = {'username': email, 'password': password, 'auth_type': 'email'};
      final response = await http.post(
        Uri.parse('https://auth.alignsys.tech/api/token/'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        accessToken = data['access'];
        refreshToken = data['refresh'];
        userId = _decodeJwtAndGetUserId(accessToken!);
        await saveTokens(accessToken!, refreshToken!, user: email, userIdValue: userId);
        return true;
      } else {
        throw Exception('Login failed: ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }

  // FETCH VAULTS
  Future<List<Vault>> getUserVaults() async {
    if (accessToken == null) throw Exception("User not logged in");
    try {
      final response = await http.get(
        Uri.parse('https://auth.alignsys.tech/api/user/vaults/'),
        headers: {'Authorization': 'Bearer $accessToken', 'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        vaults = data.map((v) => Vault.fromJson(v)).toList();
        notifyListeners();
        return vaults;
      } else {
        throw Exception('Failed to fetch vaults');
      }
    } catch (e) {
      throw Exception('Vault fetch error: $e');
    }
  }

  // ADD THIS METHOD - Fetch M-Files user ID for the selected vault
  Future<void> fetchMFilesUserId() async {
    if (selectedVault == null || accessToken == null) {
      print('⚠️ Cannot fetch M-Files user ID: vault or token missing');
      return;
    }

    try {
      print('🔍 Fetching M-Files user ID for vault: ${selectedVault!.guid}');
      
      // Try to get from your API - adjust endpoint based on your API docs
      final response = await http.get(
        Uri.parse('$baseUrl/api/user/mfiles-profile/${selectedVault!.guid}'),
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        mfilesUserId = data['id']; // Adjust based on actual response structure
        
        print('✅ M-Files user ID: $mfilesUserId');
        
        // Save it
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('mfiles_user_id', mfilesUserId!);
        
        notifyListeners();
      } else {
        print('❌ Failed to fetch M-Files user ID: ${response.statusCode}');
        // Fallback: use a hardcoded mapping
        _useFallbackMapping();
      }
    } catch (e) {
      print('❌ Error fetching M-Files user ID: $e');
      // Fallback: use a hardcoded mapping
      _useFallbackMapping();
    }
  }

  // Fallback if API endpoint doesn't exist
  void _useFallbackMapping() {
    print('⚠️ Using fallback M-Files user ID mapping');
    // Temporary hardcoded mapping until backend provides an endpoint
    if (userId == 37) {
      mfilesUserId = 20; // Map your auth ID to M-Files ID
      print('✅ Mapped auth user $userId to M-Files user $mfilesUserId');
    } else {
      mfilesUserId = userId; // Default: assume they're the same
    }
    notifyListeners();
  }

  // FETCH OBJECT TYPES - Updated to use mfilesUserId
  Future<void> fetchObjectTypes() async {
    if (selectedVault == null || mfilesUserId == null) {
      print('⚠️ Cannot fetch object types: vault or M-Files user ID missing');
      return;
    }
    _setLoading(true);
    _setError(null);
    try {
      final url = Uri.parse('$baseUrl/api/MfilesObjects/GetVaultsObjects/${selectedVault!.guid}/$mfilesUserId');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $accessToken'});
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

  // FETCH OBJECT CLASSES - Updated to use mfilesUserId
  Future<void> fetchObjectClasses(int objectTypeId) async {
    if (selectedVault == null || mfilesUserId == null) return;
    _setLoading(true);
    _setError(null);
    try {
      final url = Uri.parse('$baseUrl/api/MfilesObjects/GetObjectClasses/${selectedVault!.guid}/$objectTypeId/$mfilesUserId');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $accessToken'});
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

  // FETCH CLASS PROPERTIES - Updated to use mfilesUserId
  Future<void> fetchClassProperties(int objectTypeId, int classId) async {
    if (selectedVault == null || mfilesUserId == null) return;
    _setLoading(true);
    _setError(null);
    try {
      final url = Uri.parse('$baseUrl/api/MfilesObjects/ClassProps/${selectedVault!.guid}/$objectTypeId/$classId/$mfilesUserId');
      final response = await http.get(url, headers: {'Authorization': 'Bearer $accessToken'});
      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        classProperties = data.map((e) => ClassProperty.fromJson(e)).toList();
        
        // ADD THIS DEBUG CODE
        print('📋 Properties for class $classId:');
        for (final prop in classProperties) {
          print('   ID: ${prop.id}, Title: "${prop.title}", Type: ${prop.propertyType}, Required: ${prop.isRequired}');
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

  // HELPERS REQUIRED BY HOME SCREEN
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

  // SEARCH VAULT OBJECTS
  Future<void> searchVault(String query) async {
    if (selectedVault == null || mfilesUserId == null || accessToken == null) {
      return;
    }

    _setLoading(true);
    _setError(null);

    try {
      final encodedQuery = Uri.encodeComponent(query);

      final url = Uri.parse(
        '$baseUrl/api/objectinstance/Search/'
        '${selectedVault!.guid}/$encodedQuery/$mfilesUserId',
      );

      print('🔍 Searching vault: $url');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      print('📨 Search response: ${response.statusCode}');
      print('📨 Search body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        recentObjects = data.map((e) => ViewObject.fromJson(e)).toList();
        notifyListeners();
      } else {
        _setError('Search failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Search error: $e');
      _setError('Search error: $e');
    } finally {
      _setLoading(false);
    }
  }


  // FILE UPLOAD
  Future<String?> uploadFile(File file) async {
    _setLoading(true);
    _setError(null);
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/objectinstance/FilesUploadAsync'),
      );
      request.files.add(await http.MultipartFile.fromPath('formFiles', file.path));
      request.headers['Authorization'] = 'Bearer $accessToken';
      final response = await request.send();
      final body = await response.stream.bytesToString();
      if (response.statusCode == 200) {
        return json.decode(body)['uploadID'];
      } else {
        _setError('File upload failed: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _setError('Error uploading file: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // Fetch lookup items for a property - Updated to use mfilesUserId
  Future<List<LookupItem>> fetchLookupItems(int propertyId) async {
    print('🔍 Fetching lookup items for propertyId: $propertyId');

    if (selectedVault == null || mfilesUserId == null) return [];

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/ValuelistInstance/${selectedVault!.guid}/$propertyId/$mfilesUserId',
      );

      print('Calling: $url');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      print('Response status: ${response.statusCode}');
      print('Response body: ${response.body}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        final items = data.map((e) => LookupItem.fromJson(e)).toList();
        print('✅ Fetched ${items.length} lookup items');
        return items;
      } else {
        print('❌ Failed with status: ${response.statusCode}');
        _setError('Failed to fetch lookup items: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Exception: $e');
      _setError('Error fetching lookup items: $e');
      return [];
    } finally {
      _setLoading(false);
    }
  }

  // CREATE OBJECT - Updated to use mfilesUserId
  Future<bool> createObject(ObjectCreationRequest request) async {
  _setLoading(true);
  _setError(null);

  try {
    if (selectedVault == null) {
      _setError('No vault selected');
      return false;
    }
    if (accessToken == null) {
      _setError('Not authenticated');
      return false;
    }
    if (mfilesUserId == null) {
      _setError('M-Files user ID not set');
      return false;
    }

    final url = Uri.parse('$baseUrl/api/objectinstance/ObjectCreation');

    final vaultGuidWithBraces = selectedVault!.guid; // KEEP braces, your API expects them here

    // Decide which payload format to use:
    // - Non-document objects (no uploadId): use FLAT payload (matches Alignsys web client; avoids title error)
    // - Document objects (uploadId exists): use WRAPPED payload (VaultGuid/UserID/mfilesCreate)
    final bool isDocumentCreate = request.uploadId != null;

    final Map<String, dynamic> body;

    if (!isDocumentCreate) {
      // ✅ FLAT payload (WORKS for Cars/Staff based on your test)
      body = {
        "objectTypeID": request.objectTypeID,
        "objectID": request.objectID,
        "classID": request.classID,
        "properties": request.properties.map((p) => p.toJson()).toList(),
        "vaultGuid": vaultGuidWithBraces,
        "userID": mfilesUserId,
      };
    } else {
      // ✅ WRAPPED payload (use for documents if your backend requires it)
      body = {
        "VaultGuid": vaultGuidWithBraces,
        "UserID": mfilesUserId,
        "mfilesCreate": {
          "objectID": request.objectID,
          "classID": request.classID,
          "properties": request.properties.map((p) => p.toJson()).toList(),
          "uploadId": request.uploadId,
        },
      };
    }

    print('🚀 Creating object at: $url');
    print('📦 Request body: ${jsonEncode(body)}');

    final response = await http.post(
      url,
      headers: {
        'Authorization': 'Bearer $accessToken',
        'Content-Type': 'application/json',
      },
      body: jsonEncode(body),
    );

    print('📨 Response Status: ${response.statusCode}');
    print('📨 Response Body: ${response.body}');
    print('📨 Response Headers: ${response.headers}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      print('✅ Object created successfully: ${response.body}');
      return true;
    }

    _setError('Server returned ${response.statusCode}: ${response.body}');
    return false;
  } catch (e) {
    _setError('Error creating object: $e');
    return false;
  } finally {
    _setLoading(false);
  }
}



  List<ViewItem> allViews = [];
  List<ViewItem> commonViews = [];
  List<ViewItem> otherViews = [];
  List<ViewObject> recentObjects = [];
  List<ViewObject> assignedObjects = [];
  String currentTab = 'Home';

  // Fetch all views
  Future<void> fetchAllViews() async {
  if (selectedVault == null || mfilesUserId == null) return;

  _setLoading(true);
  _setError(null);

  try {
    final url = Uri.parse(
      '$baseUrl/api/Views/GetViews/${selectedVault!.guid}/$mfilesUserId',
    );

    print('🔍 Fetching views from: $url');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    print('📨 Views Response: ${response.statusCode}');
    print('📨 Views Body: ${response.body}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as Map<String, dynamic>;
      
      // Parse commonViews
      if (data['commonViews'] != null) {
        final commonViewsList = data['commonViews'] as List;
        commonViews = commonViewsList.map((e) => ViewItem.fromJson(e)).toList();
        print('✅ Fetched ${commonViews.length} common views');
      }
      
      // Parse otherViews (if they exist in response)
      if (data['otherViews'] != null) {
        final otherViewsList = data['otherViews'] as List;
        otherViews = otherViewsList.map((e) => ViewItem.fromJson(e)).toList();
        print('✅ Fetched ${otherViews.length} other views');
      } else {
        // If no otherViews in response, set to empty
        otherViews = [];
        print('ℹ️ No other views in response');
      }
      
      // Combine all views
      allViews = [...commonViews, ...otherViews];
      print('✅ Total views: ${allViews.length}');
      
      notifyListeners();
    } else {
      _setError('Failed to fetch views: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ Error fetching views: $e');
    _setError('Error fetching views: $e');
  } finally {
    _setLoading(false);
  }
}
  // Fetch recent objects
  Future<void> fetchRecentObjects() async {
  if (selectedVault == null || mfilesUserId == null) return;

  _setLoading(true);
  _setError(null);

  try {
    final url = Uri.parse(
      '$baseUrl/api/Views/GetRecent/${selectedVault!.guid}/$mfilesUserId',
    );

    print('🔍 Fetching recent objects from: $url');

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    print('📨 Recent Response: ${response.statusCode}');

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;

      // Parse
      final fetched = data
          .map((e) => ViewObject.fromJson(e as Map<String, dynamic>))
          .toList();

      // Sort newest → oldest
      fetched.sort((a, b) {
        final ad = a.lastModifiedUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bd = b.lastModifiedUtc ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bd.compareTo(ad);
      });

      // Assign once
      recentObjects = fetched;

      print('✅ Fetched ${recentObjects.length} recent objects (sorted newest first)');
      notifyListeners();
    } else {
      _setError('Failed to fetch recent objects: ${response.statusCode}');
    }
  } catch (e) {
    print('❌ Error fetching recent objects: $e');
    _setError('Error fetching recent objects: $e');
  } finally {
    _setLoading(false);
  }
}

  // Fetch assigned objects
  Future<void> fetchAssignedObjects() async {
    if (selectedVault == null || mfilesUserId == null) return;

    _setLoading(true);
    _setError(null);

    try {
      final url = Uri.parse(
        '$baseUrl/api/Views/GetAssigned/${selectedVault!.guid}/$mfilesUserId',
      );

      print('🔍 Fetching assigned objects from: $url');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      print('📨 Assigned Response: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        assignedObjects = data.map((e) => ViewObject.fromJson(e)).toList();
        print('✅ Fetched ${assignedObjects.length} assigned objects');
        notifyListeners();
      } else {
        _setError('Failed to fetch assigned objects: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Error fetching assigned objects: $e');
      _setError('Error fetching assigned objects: $e');
    } finally {
      _setLoading(false);
    }
  }

  // Get objects in a specific view
  Future<List<ViewObject>> fetchObjectsInView(int viewId, List<int> objectIds) async {
    if (selectedVault == null || mfilesUserId == null) return [];

    try {
      final url = Uri.parse(
        '$baseUrl/api/Views/GetViewObjects/${selectedVault!.guid}/$viewId/${objectIds.join(',')}/$mfilesUserId',
      );

      print('🔍 Fetching objects in view $viewId');

      final response = await http.get(
        url,
        headers: {'Authorization': 'Bearer $accessToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data.map((e) => ViewObject.fromJson(e)).toList();
      }
      return [];
    } catch (e) {
      print('❌ Error fetching view objects: $e');
      return [];
    }
  }

  // Set active tab
  void setActiveTab(String tab) {
    currentTab = tab;
    notifyListeners();
  }

  // Fetch objects for a specific view
  Future<List<ViewObject>> fetchObjectsForView(int viewId) async {
  if (selectedVault == null || mfilesUserId == null || accessToken == null) return [];

  final url = Uri.parse('$baseUrl/api/Views/GetObjectsInView').replace(
    queryParameters: {
      'VaultGuid': selectedVault!.guid,
      'viewid': viewId.toString(),
      'UserID': mfilesUserId.toString(),
    },
  );

  print('🔍 GetObjectsInView URL: $url');

  final resp = await http.get(
    url,
    headers: {'Authorization': 'Bearer $accessToken'},
  );

  print('📨 GetObjectsInView status: ${resp.statusCode}');
  print('📨 GetObjectsInView body: ${resp.body}');

  if (resp.statusCode != 200) {
    throw Exception('GetObjectsInView failed: ${resp.statusCode} ${resp.body}');
  }

  final data = json.decode(resp.body) as List;

  return data.map<ViewObject>((e) {
    final m = e as Map<String, dynamic>;

    DateTime? dt(String? s) => s == null ? null : DateTime.tryParse(s);

    return ViewObject(
      id: (m['id'] as num?)?.toInt() ?? 0,
      title: (m['title'] as String?) ?? '',

      objectTypeId: (m['objectTypeId'] as num?)?.toInt() ?? 0,
      classId: (m['classId'] as num?)?.toInt() ?? 0,
      versionId: (m['versionId'] as num?)?.toInt() ?? 0,

      objectTypeName: (m['objectTypeName'] as String?) ?? '',
      classTypeName: (m['classTypeName'] as String?) ?? '',
      displayId: (m['displayID'] as String?) ?? (m['displayId'] as String?) ?? '',

      createdUtc: dt(m['createdUtc'] as String?),
      lastModifiedUtc: dt(m['lastModifiedUtc'] as String?),
    );
  }).toList();
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
    '${selectedVault!.guid}/$objectId/$classId/$mfilesUserId',
  );

  final resp = await http.get(url, headers: {'Authorization': 'Bearer $accessToken'});

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

Future<void> updateObjectProps({
  required int objectId,
  required int objectTypeId,
  required int classId,
  required List<Map<String, dynamic>> props, // [{id,value,datatype}]
}) async {
  if (selectedVault == null || mfilesUserId == null || accessToken == null) {
    throw Exception('Session not ready');
  }

  final url = Uri.parse('$baseUrl/api/objectinstance/UpdateObjectProps');

  final body = {
    "objectypeid": objectTypeId,
    "objectid": objectId,
    "classid": classId,
    "props": props,
    "vaultGuid": selectedVault!.guid,
    "userID": mfilesUserId,
  };

  final resp = await http.post(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: json.encode(body),
  );

  if (resp.statusCode == 200 || resp.statusCode == 204) return;

  throw Exception('UpdateObjectProps failed: ${resp.statusCode} ${resp.body}');
}

//Drill-down service call for group folders
Future<List<ViewContentItem>> fetchObjectsInViewRaw(int viewId) async {
  if (selectedVault == null || mfilesUserId == null || accessToken == null) return [];

  final url = Uri.parse('$baseUrl/api/Views/GetObjectsInView').replace(
    queryParameters: {
      'VaultGuid': selectedVault!.guid,
      'viewid': viewId.toString(),
      'UserID': mfilesUserId.toString(),
    },
  );

  final resp = await http.get(url, headers: {'Authorization': 'Bearer $accessToken'});
  if (resp.statusCode != 200) {
    throw Exception('GetObjectsInView failed: ${resp.statusCode} ${resp.body}');
  }

  final data = json.decode(resp.body) as List;
  return data.map((e) => ViewContentItem.fromJson(e as Map<String, dynamic>)).toList();
}

// Fetch objects for a specific view property
Future<List<ViewObject>> fetchViewPropObjects({
  required int viewId,
  required String propId,
  required String propDatatype,
  required String value,
}) async {
  if (selectedVault == null || mfilesUserId == null || accessToken == null) return [];

  final url = Uri.parse('$baseUrl/api/Views/GetViewPropObjects');

  final rawVault = selectedVault!.guid;
final cleanVault = rawVault.replaceAll(RegExp(r'[{}]'), '');

  final body = {
    // vault variants
    "vaultGuid": cleanVault,
    "VaultGuid": cleanVault,
    "vaultGUID": cleanVault,

    // user variants
    "userID": mfilesUserId,
    "UserID": mfilesUserId,

    // view id variants
    "viewId": viewId,
    "viewID": viewId,
    "viewid": viewId,
    "ViewId": viewId,
    "ViewID": viewId,
    "Viewid": viewId,

    // property info
    "propId": propId,
    "PropId": propId,
    "propDatatype": propDatatype,
    "PropDatatype": propDatatype,

    // grouping value
    "value": value,
    "Value": value,
  };

  print('GetViewPropObjects viewId=$viewId propId=$propId datatype=$propDatatype value=$value');
  print('GetViewPropObjects body=$body');

  print('POST URL: $url');


  final resp = await http.post(
    url,
    headers: {
      'Authorization': 'Bearer $accessToken',
      'Content-Type': 'application/json',
    },
    body: json.encode(body),
  );

  if (resp.statusCode != 200) {
    throw Exception('GetViewPropObjects failed: ${resp.statusCode} ${resp.body}');
  }

  final data = json.decode(resp.body) as List;
  return data.map((e) => ViewObject.fromJson(e as Map<String, dynamic>)).toList();
}

// Fetch deleted objects - Updated to use mfilesUserId
Future<void> fetchDeletedObjects() async {
  if (selectedVault == null || mfilesUserId == null) return;

  _setLoading(true);
  _setError(null);

  try {
    final url = Uri.parse(
      '$baseUrl/api/ObjectDeletion/GetDeletedObject/'
      '${selectedVault!.guid}/$mfilesUserId',
    );

    final response = await http.get(
      url,
      headers: {'Authorization': 'Bearer $accessToken'},
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body) as List;

      deletedObjects = data
          .map((e) => ViewObject.fromJson(e as Map<String, dynamic>))
          .toList();

      notifyListeners();
    } else {
      _setError('Failed to fetch deleted objects: ${response.statusCode}');
    }
  } catch (e) {
    _setError('Error fetching deleted objects: $e');
  } finally {
    _setLoading(false);
  }
}
// Fetch report objects (stub implementation) for icon purposes now only (endpoint missing)
  Future<void> fetchReportObjects() async {
  reportObjects = [];
  notifyListeners();
}

Future<List<Map<String, dynamic>>> fetchLookupOptions(int propertyId) async {
  // TODO: replace with your actual endpoint
  // Return: [{ "id": 1, "name": "David Larry" }, ...]
  throw UnimplementedError('Wire fetchLookupOptions(propertyId: $propertyId) to your API');
}

}