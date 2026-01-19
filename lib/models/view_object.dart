class ViewObject {
  final int id; // object id
  final String title;

  final int objectTypeId;
  final int classId;
  final int versionId;

  final String objectTypeName;
  final String classTypeName;
  final String displayId;

  final DateTime? createdUtc;
  final DateTime? lastModifiedUtc;

  ViewObject({
    required this.id,
    required this.title,
    required this.objectTypeId,
    required this.classId,
    required this.versionId,
    required this.objectTypeName,
    required this.classTypeName,
    required this.displayId,
    required this.createdUtc,
    required this.lastModifiedUtc,
  });

  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory ViewObject.fromJson(Map<String, dynamic> json) {
    return ViewObject(
      id: (json['id'] as num?)?.toInt() ?? (json['objectId'] as num?)?.toInt() ?? 0,
      title: (json['title'] as String?) ?? '',

      objectTypeId: (json['objectTypeId'] as num?)?.toInt() ?? 0,
      classId: (json['classId'] as num?)?.toInt() ?? 0,
      versionId: (json['versionId'] as num?)?.toInt() ?? 0,

      objectTypeName: (json['objectTypeName'] as String?) ?? '',
      classTypeName: (json['classTypeName'] as String?) ?? '',
      displayId: (json['displayID'] as String?) ?? (json['displayId'] as String?) ?? '',

      createdUtc: _dt(json['createdUtc']),
      lastModifiedUtc: _dt(json['lastModifiedUtc']),
    );
  }
}
