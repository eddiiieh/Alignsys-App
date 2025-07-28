class ClassProperty {
  final int id;
  final String name;
  final String title;
  final int propId;
  final String displayName;
  final String propertyType;
  final bool isRequired;
  final bool isAutomatic;
  final bool isHidden;
  final String? defaultValue;
  final List<PropertyValue>? valuelist;

  ClassProperty({
    required this.id,
    required this.name,
    required this.title,
    required this.propId,
    required this.displayName,
    required this.propertyType,
    required this.isRequired,
    required this.isAutomatic,
    required this.isHidden,
    this.defaultValue,
    this.valuelist,
  });
  factory ClassProperty.fromJson(Map<String, dynamic> json) {
    return ClassProperty(
      id: (json['propId'] as num?)?.toInt() ?? 0,
      name: json['title'] ?? 'Unnamed Property',
      title: json['title'] ?? 'Unnamed Property',
      propId: json['propId'] ?? 0,
      displayName: json['title'] ?? 'Unnamed Property',
      propertyType: json['propertytype'] ?? 'MFDatatypeText', // Use the already parsed value
      isRequired: json['isRequired'] ?? false,
      isAutomatic: json['isAutomatic'] ?? false,
      isHidden: json['isHidden'] ?? false,
      defaultValue: null,
      valuelist: (json['valuelist'] as List<dynamic>?)
          ?.map((item) => PropertyValue.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
  
  Map<String, dynamic> toJson() => {
        'propertyDef': id,
        'propertyName': name,
        'dataType': propertyType,
        'isRequired': isRequired,
        'isAutomatic': isAutomatic,
        'isHidden': isHidden,
        'defaultValue': defaultValue,
        'valueList': valuelist?.map((v) => v.toJson()).toList(),
      };
}
class PropertyValue {
  final String displayValue;
  final dynamic value;
  PropertyValue({
    required this.displayValue,
    required this.value,
  });
  factory PropertyValue.fromJson(Map<String, dynamic> json) {
    return PropertyValue(
      displayValue: json['DisplayValue'] ?? '',
      value: json['Value'],
    );
  }
  Map<String, dynamic> toJson() => {
        'DisplayValue': displayValue,
        'Value': value,
      };
}