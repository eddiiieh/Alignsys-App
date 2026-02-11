// lib/services/mfiles_debugger.dart
import 'dart:convert';
import 'package:http/http.dart' as http;

class MFilesDebugger {
  final String baseUrl;
  final Map<String, String> headers;

  MFilesDebugger(this.baseUrl, this.headers);

  // Step 1: Validate ObjectType and Class exist
  Future<void> validateObjectTypeAndClass(int objectTypeId, int classId) async {
    print('🔍 Validating ObjectType $objectTypeId and Class $classId...');
    
    // Check ObjectType
    try {
      final otResponse = await http.get(
        Uri.parse('$baseUrl/REST/structure/objecttypes/$objectTypeId'),
        headers: headers,
      );
      
      if (otResponse.statusCode == 200) {
        final otData = json.decode(otResponse.body);
        print('✅ ObjectType $objectTypeId: ${otData['Name']}');
      } else {
        print('❌ ObjectType $objectTypeId not found or invalid');
        return;
      }
    } catch (e) {
      print('❌ Error checking ObjectType: $e');
      return;
    }

    // Check Class
    try {
      final classResponse = await http.get(
        Uri.parse('$baseUrl/REST/structure/classes/$classId'),
        headers: headers,
      );
      
      if (classResponse.statusCode == 200) {
        final classData = json.decode(classResponse.body);
        print('✅ Class $classId: ${classData['Name']}');
        print('   ObjectType: ${classData['ObjectType']}');
        
        // Verify class belongs to the right object type
        if (classData['ObjectType'] != objectTypeId) {
          print('❌ Class $classId does not belong to ObjectType $objectTypeId');
          print('   Expected: $objectTypeId, Got: ${classData['ObjectType']}');
        }
      } else {
        print('❌ Class $classId not found or invalid');
      }
    } catch (e) {
      print('❌ Error checking Class: $e');
    }
  }

  // Step 2: Get all required properties for the class
  Future<List<Map<String, dynamic>>> getRequiredProperties(int classId) async {
    print('🔍 Getting required properties for Class $classId...');
    
    try {
      final response = await http.get(
        Uri.parse('$baseUrl/REST/structure/classes/$classId/properties'),
        headers: headers,
      );
      
      if (response.statusCode == 200) {
        final List<dynamic> properties = json.decode(response.body);
        final requiredProps = properties.where((prop) => prop['Required'] == true).toList();
        
        print('📋 Required properties for Class $classId:');
        for (var prop in requiredProps) {
          print('   - PropertyDef ${prop['ID']}: ${prop['Name']} (DataType: ${prop['DataType']})');
        }
        
        return requiredProps.cast<Map<String, dynamic>>();
      } else {
        print('❌ Failed to get class properties: ${response.statusCode}');
        return [];
      }
    } catch (e) {
      print('❌ Error getting class properties: $e');
      return [];
    }
  }

  // Step 3: Validate specific property definitions
  Future<void> validateProperties(List<int> propertyIds) async {
    print('🔍 Validating property definitions...');
    
    for (int propId in propertyIds) {
      try {
        final response = await http.get(
          Uri.parse('$baseUrl/REST/structure/properties/$propId'),
          headers: headers,
        );
        
        if (response.statusCode == 200) {
          final propData = json.decode(response.body);
          print('✅ PropertyDef $propId: ${propData['Name']} (DataType: ${propData['DataType']})');
        } else {
          print('❌ PropertyDef $propId not found or invalid');
        }
      } catch (e) {
        print('❌ Error checking PropertyDef $propId: $e');
      }
    }
  }

  // Step 4: Create minimal test object
  Future<void> testMinimalObject(int objectTypeId, int classId) async {
    print('🔍 Testing minimal object creation...');
    
    // Try with just the Name property (PropertyDef 0)
    final minimalPayload = {
      'ObjectTypeId': objectTypeId,
      'ClassId': classId,
      'PropertyValues': [
        {
          'PropertyDef': 0, // Name property
          'TypedValue': {
            'DataType': 1,
            'Value': 'Test Object ${DateTime.now().millisecondsSinceEpoch}',
            'HasValue': true,
          }
        }
      ]
    };

    try {
      final response = await http.post(
        Uri.parse('$baseUrl/REST/objects'),
        headers: headers,
        body: json.encode(minimalPayload),
      );

      print('📤 Minimal payload: ${json.encode(minimalPayload)}');
      print('📥 Response status: ${response.statusCode}');
      print('📥 Response body: ${response.body}');

      if (response.statusCode == 200) {
        print('✅ Minimal object creation successful!');
      } else {
        print('❌ Even minimal object creation failed');
      }
    } catch (e) {
      print('❌ Error creating minimal object: $e');
    }
  }

  // Complete debugging workflow
  Future<void> debugObjectCreation(int objectTypeId, int classId, List<int> propertyIds) async {
    print('🚀 Starting M-Files Object Creation Debug...\n');
    
    // Step 1: Validate ObjectType and Class
    await validateObjectTypeAndClass(objectTypeId, classId);
    print('');
    
    // Step 2: Get required properties
    await getRequiredProperties(classId);
    print('');
    
    // Step 3: Validate your property IDs
    await validateProperties(propertyIds);
    print('');
    
    // Step 4: Test minimal object
    await testMinimalObject(objectTypeId, classId);
    print('');
    
    print('🔧 Debugging complete! Check the output above.');
  }
}