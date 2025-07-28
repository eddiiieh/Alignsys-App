class LookupItem {
  final int id;
  final String displayValue;

  LookupItem({required this.id, required this.displayValue});

  factory LookupItem.fromJson(Map<String, dynamic> json) {
    return LookupItem(
      id: json['id'],
      displayValue: json['name'], // ✅ Changed from 'displayValue' to 'name'
    );
  }
  
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': displayValue, // Keep original API format when sending back
    };
  }
}