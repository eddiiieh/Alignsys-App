class ObjectComment {
  final String author;
  final String text;
  final DateTime? modifiedDate;

  ObjectComment({
    required this.author,
    required this.text,
    required this.modifiedDate,
  });

  /// The web app stores comments as "AuthorName : comment text".
  /// Split on the FIRST " : " to separate author from text.
  /// If no separator exists, author is empty and the whole value is text.
  static ({String author, String text}) _splitComent(String raw) {
    const sep = ' : ';
    final idx = raw.indexOf(sep);
    if (idx <= 0) return (author: '', text: raw.trim());
    return (
      author: raw.substring(0, idx).trim(),
      text: raw.substring(idx + sep.length).trim(),
    );
  }

  /// Parses the backend date format: "M/d/yyyy h:mm AM/PM"
  /// e.g. "3/4/2026 11:25 AM" or "9/24/2024 1:33 PM"
  static DateTime? _parseDate(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // Try ISO first (future-proofing)
    try {
      return DateTime.parse(s);
    } catch (_) {}

    // Parse "M/d/yyyy h:mm AM/PM"
    try {
      final parts = s.split(' ');
      if (parts.length < 3) return null;

      final dateParts = parts[0].split('/');
      if (dateParts.length != 3) return null;
      final month = int.parse(dateParts[0]);
      final day   = int.parse(dateParts[1]);
      final year  = int.parse(dateParts[2]);

      final timeParts = parts[1].split(':');
      if (timeParts.length != 2) return null;
      int hour     = int.parse(timeParts[0]);
      final minute = int.parse(timeParts[1]);

      final isPm = parts[2].toUpperCase() == 'PM';
      if (isPm && hour != 12) hour += 12;
      if (!isPm && hour == 12) hour = 0;

      return DateTime(year, month, day, hour, minute);
    } catch (_) {
      return null;
    }
  }

  factory ObjectComment.fromJson(Map<String, dynamic> json) {
    // API uses "coment" (typo in backend). Support both spellings.
    final raw = (json['comment'] ?? json['coment'] ?? '').toString();
    final parsed = _splitComent(raw);

    return ObjectComment(
      author: parsed.author,
      text: parsed.text,
      modifiedDate: _parseDate(json['modifiedDate']),
    );
  }
}