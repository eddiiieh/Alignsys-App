class ObjectClass {
  final int id;
  final String name;
  final int objectTypeId;

  ObjectClass({
    required this.id,
    required this.name,
    required this.objectTypeId,
  });

  factory ObjectClass.fromJson(Map<String, dynamic> json, int objectTypeId) {
    return ObjectClass(
      id: (json['classId'] as num?)?.toInt() ?? 0,
      name: json['className'] ?? 'Unnamed Class',
      objectTypeId: objectTypeId,
    );
  }

  String get displayName => name;

  Map<String, dynamic> toJson() => {
        'classId': id,
        'className': name,
        'objectTypeId': objectTypeId,
      };
}

// Add this to your models/object_class.dart
class ClassGroup {
  final int classGroupId;
  final String classGroupName;
  final List<ObjectClass> members;

  ClassGroup({
    required this.classGroupId,
    required this.classGroupName,
    required this.members,
  });

  factory ClassGroup.fromJson(Map<String, dynamic> json, int objectTypeId) {
    return ClassGroup(
      classGroupId: json['classGroupId'],
      classGroupName: json['classGroupName'],
      members: (json['members'] as List)
          .map((item) => ObjectClass.fromJson(item, objectTypeId))
          .toList(),
    );
  }
}

class ObjectClassesResponse {
  final int objectId;
  final List<ObjectClass> unGrouped;
  final List<ClassGroup> grouped;

  ObjectClassesResponse({
    required this.objectId,
    required this.unGrouped,
    required this.grouped,
  });

  factory ObjectClassesResponse.fromJson(Map<String, dynamic> json) {
    final objectTypeId = json['objectId'];
    return ObjectClassesResponse(
      objectId: objectTypeId,
      unGrouped: (json['unGrouped'] as List)
          .map((item) => ObjectClass.fromJson(item, objectTypeId))
          .toList(),
      grouped: (json['grouped'] as List)
          .map((item) => ClassGroup.fromJson(item, objectTypeId))
          .toList(),
    );
  }
}
