class ObjectCreationRequest {
  final int objectID;
  final int objectTypeID; // ADD
  final int classID;
  final List<PropertyValueRequest> properties;
  final String vaultGuid;
  final String? uploadId;
  final int userID;

  ObjectCreationRequest({
    required this.objectID,
    required this.objectTypeID, // ADD
    required this.classID,
    required this.properties,
    required this.vaultGuid,
    required this.userID,
    this.uploadId,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'objectID': objectID,
      'objectTypeID': objectTypeID, // ADD
      'classID': classID,
      'properties': properties.map((pv) => pv.toJson()).toList(),
      'vaultGuid': vaultGuid,
      'userID': userID,
    };

    if (uploadId != null) json['uploadId'] = uploadId;
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
      'value': _formatValueForAPI(value, propertyType), // USE IT
      'propertytype': propertyType,
    };
  }

  static String _formatValueForAPI(dynamic value, String propertyType) {
    if (value == null) return '';

    switch (propertyType) {
      case 'MFDatatypeLookup':
        return value.toString(); // "18"

      case 'MFDatatypeMultiSelectLookup':
        // web client sends string; for multiple, send comma-separated
        if (value is List) return value.map((id) => id.toString()).join(',');
        return value.toString();

      case 'MFDatatypeBoolean':
        if (value is bool) return value ? 'true' : 'false';
        final s = value.toString().toLowerCase();
        return (s == 'true' || s == '1') ? 'true' : 'false';

      case 'MFDatatypeDate':
        // enforce YYYY-MM-DD even if an ISO datetime sneaks in
        final s = value.toString();
        return s.contains('T') ? s.split('T').first : s;

      default:
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
        return value;
      case 2: // Integer
        return value is int ? value : int.tryParse(value) ?? 0;
      case 3: // Floating
        return value is double ? value : double.tryParse(value) ?? 0.0;
      case 5: // Date
        // Value should already be formatted as YYYY-MM-DD from PropertyFormField
        return value;
      case 7: // DateTime/Timestamp
        // Value should already be formatted as YYYY-MM-DDTHH:MM:SS.000Z from PropertyFormField
        return value;
      case 8: // Boolean
        return value is bool ? value : (value.toLowerCase() == 'true');
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