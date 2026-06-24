class LookupItem {
  final int id;
  final String displayValue;
  final int? objectTypeId; // ← add this

  LookupItem({
    required this.id,
    required this.displayValue,
    this.objectTypeId,       // ← optional, won't break existing callers
  });

  factory LookupItem.fromJson(Map<String, dynamic> json) {
    return LookupItem(
      id: json['id'],
      displayValue: json['name'],
      objectTypeId: json['objectTypeId'] as int?, // ← add this
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': displayValue,
      'objectTypeId': objectTypeId,
    };
  }
}