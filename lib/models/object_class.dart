class ClassWorkflowRef {
  final int id;
  final String? alias;

  ClassWorkflowRef({required this.id, this.alias});

  factory ClassWorkflowRef.fromJson(Map<String, dynamic>? json) {
    if (json == null) return ClassWorkflowRef(id: 0, alias: null);
    return ClassWorkflowRef(
      id: (json['id'] as num?)?.toInt() ?? 0,
      alias: json['alias'] as String?,
    );
  }
}
class ObjectClass {
  final int id;
  final String name;
  final int objectTypeId;
  final String alias; // ← add: the class's own alias
  final ClassWorkflowRef defaultWorkflow; // ← add: the class's assigned workflow
  final ClassWorkflowRef defaultState;

  ObjectClass({
    required this.id,
    required this.name,
    required this.objectTypeId,
    required this.alias,
    required this.defaultWorkflow,
    required this.defaultState,
  });

  factory ObjectClass.fromJson(Map<String, dynamic> json, int objectTypeId) {
    return ObjectClass(
      id: (json['classId'] as num?)?.toInt() ?? 0,
      name: json['className'] ?? 'Unnamed Class',
      objectTypeId: objectTypeId,
      alias: (json['alias'] as String?) ?? '',
      defaultWorkflow: ClassWorkflowRef.fromJson(
        json['defaultwf'] as Map<String, dynamic>?,
      ),
      defaultState: ClassWorkflowRef.fromJson(
        json['state'] as Map<String, dynamic>?,
      ),
    );
  }

  String get displayName => name;

  Map<String, dynamic> toJson() => {
        'classId': id,
        'className': name,
        'objectTypeId': objectTypeId,
        'alias': alias,
        'defaultwf': {'id': defaultWorkflow.id, 'alias': defaultWorkflow.alias},
        'state': {'id': defaultState.id, 'alias': defaultState.alias},
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
