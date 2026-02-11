class ViewContentItem {
  final String type;

  // object fields
  final int id;
  final String title;
  final int objectTypeId;
  final int classId;
  final int versionId;
  final String? objectTypeName;
  final String? classTypeName;
  final String? displayId;
  final DateTime? createdUtc;
  final DateTime? lastModifiedUtc;

  // grouping fields
  final int viewId;
  final String? propId;          // was int?
  final String? propDatatype;

  ViewContentItem({
    required this.type,
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
    required this.viewId,
    required this.propId,
    required this.propDatatype,
  });

  bool get isObject => type == 'MFFolderContentItemTypeObjectVersion' && id > 0;
  bool get isGroupFolder => type == 'MFFolderContentItemTypePropertyFolder';
  bool get isViewFolder => type == 'MFFolderContentItemTypeViewFolder' && id > 0;


  static DateTime? _dt(dynamic v) {
    if (v == null) return null;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  factory ViewContentItem.fromJson(Map<String, dynamic> m) {
    final rawPropId = m['propId'] ?? m['propID'] ?? m['propertyId'] ?? m['propertyID'];

    return ViewContentItem(
      type: (m['type'] as String?) ?? '',
      id: (m['id'] as num?)?.toInt() ?? -1,
      title: (m['title'] as String?) ?? '',
      objectTypeId: (m['objectTypeId'] as num?)?.toInt() ?? -1,
      classId: (m['classId'] as num?)?.toInt() ?? -1,
      versionId: (m['versionId'] as num?)?.toInt() ?? 0,
      objectTypeName: m['objectTypeName'] as String?,
      classTypeName: m['classTypeName'] as String?,
      displayId: (m['displayID'] as String?) ?? (m['displayId'] as String?),
      createdUtc: _dt(m['createdUtc']),
      lastModifiedUtc: _dt(m['lastModifiedUtc']),
      viewId: (m['viewId'] as num?)?.toInt() ?? -1,
      propId: rawPropId?.toString(),           // keep "05"
      propDatatype: m['propDatatype']?.toString(),
    );
  }
}
