class ObjectComment {
  final String text;
  final DateTime? modifiedDate;

  ObjectComment({required this.text, required this.modifiedDate});

  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // Backend format example: "9/24/2024 1:33 PM" (not ISO).
    // DateTime.parse won't handle this reliably, so keep it best-effort.
    // If you want strict parsing, switch to `intl` DateFormat.
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  factory ObjectComment.fromJson(Map<String, dynamic> json) {
    // Your GET sample uses "coment" (typo). Support both.
    final rawText = (json['comment'] ?? json['coment'] ?? '').toString();

    return ObjectComment(
      text: rawText,
      modifiedDate: _parseDate(json['modifiedDate']),
    );
  }
}
