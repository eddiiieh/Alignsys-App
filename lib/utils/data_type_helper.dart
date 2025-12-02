class DataTypeHelper {
  static const Map<int, String> dataTypeNames = {
    1: 'Text',
    2: 'Integer',
    3: 'Decimal',
    5: 'Date',
    6: 'Time',
    7: 'DateTime',
    8: 'Boolean',
    9: 'Lookup',
    10: 'Multi-select Lookup',
    13: 'Multi-line Text',
  };

  static String getDataTypeName(int dataType) {
    return dataTypeNames[dataType] ?? 'Unknown ($dataType)';
  }

  static bool isNumericType(int dataType) {
    return dataType == 2 || dataType == 3; // Integer or Decimal
  }

  static bool isDateTimeType(int dataType) {
    return dataType == 5 || dataType == 6 || dataType == 7; // Date, Time, or DateTime
  }

  static bool isLookupType(int dataType) {
    return dataType == 9 || dataType == 10; // Lookup or Multi-select Lookup
  }
}