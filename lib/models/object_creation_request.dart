class ObjectCreationRequest {
  final int objectTypeId;
  final int classId;
  final List<PropertyValueRequest> properties;
  final String? uploadId;

  ObjectCreationRequest({
    required this.objectTypeId,
    required this.classId,
    required this.properties,
    this.uploadId,
  });

  Map<String, dynamic> toJson() {
    final Map<String, dynamic> json = {
      'objectID': objectTypeId,
      'classID': classId,
      'properties': properties.map((pv) => pv.toJson()).toList(),
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
  final String propertytype;

  PropertyValueRequest({
    required this.propId,
    required this.value,
    required this.propertytype,
  });

  Map<String, dynamic> toJson() {
    // M-Files expects a specific format for property values
    return {
      'propId': propId,
      'value': value,
      'propertytype': propertytype, // Convert propId to M-Files data type string
    };
  }

  dynamic _formatValue(dynamic value, String type) {
    if (value == null) return null;
    
    if (type == 'MFDatatypeDate') {
      return _formatDate(value);
    }
    return value; // Return unchanged for other types
  }

  String _formatDate(dynamic input) {
    // If already in YYYY-MM-DD format, return as-is
    if (input is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(input)) {
      return input;
    }
    
    // Handle DD-MM-YYYY format
    if (input is String && input.contains('-')) {
      final parts = input.split('-');
      if (parts.length == 3) {
        // Reorder to YYYY-MM-DD
        return '${parts[2]}-${parts[1]}-${parts[0]}';
      }
    }
    
    // Fallback for other cases
    return input.toString();
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