// models/view_object.dart
class ViewObject {
  final int objectId;
  final String title;
  final String objectType;
  final DateTime? lastModified;
  final String? thumbnail;

  ViewObject({
    required this.objectId,
    required this.title,
    required this.objectType,
    this.lastModified,
    this.thumbnail,
  });

  factory ViewObject.fromJson(Map<String, dynamic> json) {
    return ViewObject(
      objectId: json['objectId'] ?? json['id'] ?? 0,
      title: json['title'] ?? json['name'] ?? 'Untitled',
      objectType: json['objectType'] ?? json['type'] ?? 'Unknown',
      lastModified: json['lastModified'] != null 
          ? DateTime.tryParse(json['lastModified'].toString())
          : json['modifiedDate'] != null
              ? DateTime.tryParse(json['modifiedDate'].toString())
              : null,
      thumbnail: json['thumbnail'],
    );
  }
}