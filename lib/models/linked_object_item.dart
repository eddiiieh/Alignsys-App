class LinkedObjectItem {
  final int id;
  final int objectID;        // objectTypeId
  final int classID;
  final String title;
  final String objectTypeName;
  final String classTypeName;
  final String displayID;

  LinkedObjectItem({
    required this.id,
    required this.objectID,
    required this.classID,
    required this.title,
    required this.objectTypeName,
    required this.classTypeName,
    required this.displayID,
  });

  factory LinkedObjectItem.fromJson(Map<String, dynamic> j) {
    int _i(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? 0}') ?? 0;
    String _s(dynamic v) => (v ?? '').toString();

    return LinkedObjectItem(
      id: _i(j['id']),
      objectID: _i(j['objectID']),
      classID: _i(j['classID']),
      title: _s(j['title']),
      objectTypeName: _s(j['objectTypeName']),
      classTypeName: _s(j['classTypeName']),
      displayID: _s(j['displayID']),
    );
  }
}


class LinkedObjectsGroup {
  final String propertyName; // e.g. "Cars"
  final List<LinkedObjectItem> items;

  LinkedObjectsGroup({required this.propertyName, required this.items});

  int get count => items.length;

  factory LinkedObjectsGroup.fromJson(Map<String, dynamic> j) {
    final raw = (j['items'] as List? ?? const []);
    return LinkedObjectsGroup(
      propertyName: (j['propertyName'] ?? '').toString(),
      items: raw.map((e) => LinkedObjectItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
