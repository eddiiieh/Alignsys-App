import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/vault_object_type.dart';
import '../models/object_class.dart';
import '../models/class_property.dart';
import '../models/lookup_item.dart';
import '../models/object_creation_request.dart';

class MFilesService extends ChangeNotifier {
  static const String baseUrl = 'https://mfilesdemoapi.alignsys.tech';

  List<VaultObjectType> _objectTypes = [];
  List<ObjectClass> _objectClasses = [];
  List<ClassProperty> _classProperties = [];
  List<ClassGroup> _classGroups = [];
  bool _isLoading = false;
  String? _error;

  List<VaultObjectType> get objectTypes => _objectTypes;
  List<ObjectClass> get objectClasses => _objectClasses;
  List<ClassProperty> get classProperties => _classProperties;
  bool get isLoading => _isLoading;
  String? get error => _error;

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }

    // Helper method to check if a class is in any group
  bool isClassInAnyGroup(int classId) {
    return _classGroups.any((group) => 
        group.members.any((cls) => cls.id == classId));
  }

  // Helper method to get groups for a specific object type
  List<ClassGroup> getClassGroupsForType(int objectTypeId) {
    return _classGroups.where((group) => 
        group.members.isNotEmpty && 
        group.members.first.objectTypeId == objectTypeId).toList();
  }

  // 1. Get Vault Object Types
  Future<void> fetchObjectTypes() async {
    _setLoading(true);
    _setError(null);

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/MfilesObjects/GetVaultsObjectsTypes'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        print('Object types API response: ${response.body}');
        final List<dynamic> data = json.decode(response.body);
        _objectTypes = data
            .map((item) => VaultObjectType.fromJson(item))
            .where((type) => type.displayName.trim().toLowerCase() != 'document collections')
            .toList();

            // Paste here to debug what is in your list
          for (var type in _objectTypes) {
            print('displayName: "${type.displayName}"');
          }
          
      } else {
        _setError('Failed to fetch object types: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching object types: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 2. Get Object Classes by Type ID
  Future<void> fetchObjectClasses(int objectTypeId) async {
  _setLoading(true);
  _setError(null);

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/MfilesObjects/GetObjectClasses/$objectTypeId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      print('Object class API response: ${response.body}');
      final data = json.decode(response.body);
      final responseData = ObjectClassesResponse.fromJson(data);
      
      // Clear existing classes and groups for this type
      _objectClasses.removeWhere((cls) => cls.objectTypeId == objectTypeId);
      _classGroups.removeWhere((group) => 
          group.members.isNotEmpty && 
          group.members.first.objectTypeId == objectTypeId);
      
      // Add all classes (both grouped and ungrouped)
      _objectClasses.addAll(responseData.unGrouped);
      
      // Store the groups
      _classGroups.addAll(responseData.grouped);
      
      // Add grouped classes to the main list too
      for (var group in responseData.grouped) {
        _objectClasses.addAll(group.members);
      }
    } else {
      _setError('Failed to fetch object classes: ${response.statusCode}');
    }
  } catch (e) {
    _setError('Error fetching object classes: $e');
  } finally {
    _setLoading(false);
  }
}


  // 3. Get Class Properties
  Future<void> fetchClassProperties(int objectTypeId, int classId) async {
    _setLoading(true);
    _setError(null);

    try {
      final response = await http.get(
        Uri.parse('$baseUrl/api/MfilesObjects/ClassProps/$objectTypeId/$classId'),
        headers: {'Content-Type': 'application/json'},
      );

      if (response.statusCode == 200) {
        print('Class properties API response: ${response.body}');
        final List<dynamic> data = json.decode(response.body);
        _classProperties = data.map((item) => ClassProperty.fromJson(item)).toList();
      } else {
        _setError('Failed to fetch class properties: ${response.statusCode}');
      }
    } catch (e) {
      _setError('Error fetching class properties: $e');
    } finally {
      _setLoading(false);
    }
  }

  // 4. Lookup Service Method
  Future<List<LookupItem>> fetchLookupItems(int propertyId) async {
  _setLoading(true);
  _setError(null);

  try {
    final response = await http.get(
      Uri.parse('$baseUrl/api/ValuelistInstance/$propertyId'),
      headers: {'Content-Type': 'application/json'},
    );

    if (response.statusCode == 200) {
      final List<dynamic> data = json.decode(response.body);
      return data.map((item) => LookupItem.fromJson(item)).toList();
    } else {
      _setError('Failed to fetch lookup items: ${response.statusCode}');
      return [];
    }
  } catch (e) {
    _setError('Error fetching lookup items: $e');
    return [];
  } finally {
    _setLoading(false);
  }
}

  // 5. Upload File (for document objects)
  Future<String?> uploadFile(File file) async {
    _setLoading(true);
    _setError(null);

    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$baseUrl/api/objectinstance/FilesUploadAsync'),
      );

      request.files.add(await http.MultipartFile.fromPath('formFiles', file.path));
      request.headers['accept'] = '*/*';
      request.headers['Content-Type'] = 'multipart/form-data';

      final response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode == 200) {
        final Map<String, dynamic> data = json.decode(responseBody);
        return data['uploadID'];
      } else {
        _setError('Failed to upload file: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      _setError('Error uploading file: $e');
      return null;
    } finally {
      _setLoading(false);
    }
  }

  // 6. Create Object
  Future<bool> createObject(ObjectCreationRequest request) async {
    _setLoading(true);
    _setError(null);

    try {

        // === PASTE DEBUG PRINT HERE ===
      final requestJson = request.toJson();
      print('Sending to M-Files API:');
      print(json.encode(requestJson)); // Pretty-print the JSON
      print('-----------------------'); // Separator for clarity
      
      print('Creating object with request: ${json.encode(request.toJson())}');
      final response = await http.post(
        Uri.parse('$baseUrl/api/objectinstance/ObjectCreation'),
        headers: {'Content-Type': 'application/json'},
        body: json.encode(request.toJson()),
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        return true;
      } else {
        print('Response body: ${response.body}');
        _setError('Failed to create object: ${response.statusCode}');
        return false;
      }
    } catch (e) {
      _setError('Error creating object: $e');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  void clearError() {
    _setError(null);
  }
}
