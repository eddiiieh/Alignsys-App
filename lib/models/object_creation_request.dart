class ObjectCreationRequest {
  final int objectID;
  final int classID;
  final List<PropertyValueRequest> properties;
  final String vaultGuid;
  final String? uploadId;
  final int userID;

  ObjectCreationRequest({
    required this.objectID,
    required this.classID,
    required this.properties,
    required this.vaultGuid,
    required this.userID,
    this.uploadId,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'objectID': objectID,
      'classID': classID,
      'properties': properties.map((pv) => pv.toJson()).toList(),
      'vaultGuid': vaultGuid,
      'userID': userID,
    };

    if (uploadId != null) {
      json['uploadId'] = uploadId;
    }

    return json;
  }
}

class PropertyValueRequest {
  final int propId;
  final dynamic value;
  final String propertyType;

  PropertyValueRequest({
    required this.propId,
    required this.value,
    required this.propertyType,
  });

  Map<String, dynamic> toJson() {
    return {
      'propId': propId,
      'value': _formatValueForAPI(value, propertyType),
      'propertytype': propertyType,
    };
  }

  /*int _getDataTypeNumber(String propertyType) {
    switch (propertyType) {
      case 'MFDatatypeText':
        return 1;
      case 'MFDatatypeMultiLineText':
        return 13;
      case 'MFDatatypeDate':
        return 5;
      case 'MFDatatypeLookup':
        return 9;
      case 'MFDatatypeMultiSelectLookup':
        return 10;
      case 'MFDatatypeBoolean':
        return 8;
      case 'MFDatatypeInteger':
        return 2;
      case 'MFDatatypeFloating':
        return 3;
      default:
        return 1; // Default to text
    }
  }*/

  dynamic _formatValueForAPI(dynamic value, String propertyType) {
    if (value == null) return null;
    
    switch (propertyType) {
      case 'MFDatatypeLookup':
        // For single lookup, send just the ID as string
        return value.toString();
        
      case 'MFDatatypeMultiSelectLookup':
        // For multi-select lookup, handle both List and single values
        if (value is List) {
          // Convert list of IDs to comma-separated string
          return value.map((id) => id.toString()).join(',');
        } else {
          // Single value
          return value.toString();
        }
        
      case 'MFDatatypeDate':
        // Keep date as string
        return value.toString();
        
      case 'MFDatatypeBoolean':
        // Convert boolean to string
        if (value is bool) {
          return value.toString();
        }
        return value.toString().toLowerCase() == 'true' ? 'true' : 'false';
        
      case 'MFDatatypeText':
      case 'MFDatatypeMultiLineText':
      default:
        // All other types as strings
        return value.toString();
    }
  }
}


// Alternative formats you might need to try if the above doesn't work:

class PropertyValueRequestAlternative {
  final int propertyId;
  final dynamic value;
  final int dataType;

  PropertyValueRequestAlternative({
    required this.propertyId,
    required this.value,
    required this.dataType,
  });

  Map<String, dynamic> toJson() {
    // Some M-Files APIs expect this format instead
    return {
      'PropertyDef': propertyId,
      'TypedValue': {
        'DataType': dataType,
        'Value': _formatValueForMFiles(value, dataType),
        'HasValue': value != null,
      }
    };
  }

  dynamic _formatValueForMFiles(dynamic value, int dataType) {
    if (value == null) return null;
    
    switch (dataType) {
      case 1: // Text
        return value.toString();
      case 2: // Integer
        return value is int ? value : int.tryParse(value.toString()) ?? 0;
      case 3: // Floating
        return value is double ? value : double.tryParse(value.toString()) ?? 0.0;
      case 5: // Date
        // Value should already be formatted as YYYY-MM-DD from PropertyFormField
        return value.toString();
      case 7: // DateTime/Timestamp
        // Value should already be formatted as YYYY-MM-DDTHH:MM:SS.000Z from PropertyFormField
        return value.toString();
      case 8: // Boolean
        return value is bool ? value : (value.toString().toLowerCase() == 'true');
      default:
        return value;
    }
  }
}

// If you need to try different date formats, here are some alternatives:

class DateTimeFormatter {
  static String formatDateForMFiles(DateTime date) {
    // Try different formats if one doesn't work:
    
    // Format 1: ISO 8601 date only
    // return date.toIso8601String().split('T')[0];
    
    // Format 2: M-Files specific format
    return '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }

  static String formatDateTimeForMFiles(DateTime dateTime) {
    // Try these formats if the current one doesn't work:
    
    // Format 1: ISO 8601 with Z
    // return dateTime.toUtc().toIso8601String();
    
    // Format 2: M-Files specific with milliseconds
    final utc = dateTime.toUtc();
    return '${utc.year.toString().padLeft(4, '0')}-${utc.month.toString().padLeft(2, '0')}-${utc.day.toString().padLeft(2, '0')}T${utc.hour.toString().padLeft(2, '0')}:${utc.minute.toString().padLeft(2, '0')}:${utc.second.toString().padLeft(2, '0')}.000Z';
    
    // Format 3: Simple format without Z
    // return '${dateTime.year.toString().padLeft(4, '0')}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}T${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}';
  }
}