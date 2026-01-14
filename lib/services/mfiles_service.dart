import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/vault_object_type.dart';
import '../models/object_class.dart';
import '../models/class_property.dart';
import '../models/lookup_item.dart';
import '../models/object_creation_request.dart';
import '../models/vault.dart';

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
      // Replace the auth userId with M-Files userId
      final updatedRequest = ObjectCreationRequest(
        objectID: request.objectID,
        classID: request.classID,
        properties: request.properties,
        vaultGuid: request.vaultGuid,
        userID: mfilesUserId ?? request.userID, // Use M-Files user ID
        uploadId: request.uploadId,
      );

      final url = Uri.parse('$baseUrl/api/objectinstance/ObjectCreation');
      
      print('🚀 Creating object at: $url');
      print('📦 Request body: ${json.encode(updatedRequest.toJson())}');
      
      final response = await http.post(
        url,
        headers: {
          'Authorization': 'Bearer $accessToken', 
          'Content-Type': 'application/json'
        },
        body: json.encode(updatedRequest.toJson()),
      );
      
      print('📨 Response Status: ${response.statusCode}');
      print('📨 Response Body: ${response.body}');
      print('📨 Response Headers: ${response.headers}');
      
      if (response.statusCode == 200 || response.statusCode == 201) {
        final responseData = json.decode(response.body);
        print('✅ Object created successfully: $responseData');
        return true;
      } else {
        _setError('Server returned ${response.statusCode}: ${response.body}');
        print('❌ Failed: ${response.statusCode} - ${response.body}');
        return false;
      }
    } catch (e) {
      _setError('Error creating object: $e');
      print('❌ Exception: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }
}