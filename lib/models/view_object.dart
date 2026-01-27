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
    int asInt(dynamic v) {
      if (v == null) return 0;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    // 👇 ADD THIS DEBUG LINE RIGHT HERE
    print(
      'PARSE ViewObject → '
      'id=${json['id']} '
      'displayID=${json['displayID']} '
      'objectID=${json['objectID']} '
      'classID=${json['classID']}',
    );

    return ViewObject(
      id: asInt(json['id']) != 0
          ? asInt(json['id'])
          : asInt(json['displayID']),
      title: (json['title'] as String?) ?? '',

      objectTypeId: asInt(json['objectID']),
      classId: asInt(json['classID']),
      versionId: asInt(json['versionId']),

      objectTypeName: (json['objectTypeName'] as String?) ?? '',
      classTypeName: (json['classTypeName'] as String?) ?? '',
      displayId: (json['displayID']?.toString()) ?? '',

      createdUtc: _dt(json['createdUtc']),
      lastModifiedUtc: _dt(json['lastModifiedUtc']),
    );
  }

}
