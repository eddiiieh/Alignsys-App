// models/view_item.dart
class ViewItem {
  final int id;
  final String name;
  final int count;
  final String? description;
  final List<GroupLevel>? groupLevels;

  ViewItem({
    required this.id,
    required this.name,
    this.count = 0,
    this.description,
    this.groupLevels,
  });

  factory ViewItem.fromJson(Map<String, dynamic> json) {
    return ViewItem(
      id: json['id'] ?? 0,
      name: json['viewName'] ?? json['name'] ?? 'Unnamed View',
      count: json['count'] ?? json['objectCount'] ?? 0,
      description: json['description'],
      groupLevels: json['groupLevels'] != null
          ? (json['groupLevels'] as List)
              .map((g) => GroupLevel.fromJson(g))
              .toList()
          : null,
    );
  }
}

class GroupLevel {
  final int id;
  final int mfilesProperty;
  final String mfilesFunction;
  final String? propertyName;

  GroupLevel({
    required this.id,
    required this.mfilesProperty,
    required this.mfilesFunction,
    this.propertyName,
  });

  factory GroupLevel.fromJson(Map<String, dynamic> json) {
    return GroupLevel(
      id: json['id'] ?? 0,
      mfilesProperty: json['mfilesproperty'] ?? 0,
      mfilesFunction: json['mfilesfunction'] ?? '',
      propertyName: json['propertyName'],
    );
  }
}