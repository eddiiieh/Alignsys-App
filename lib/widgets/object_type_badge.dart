import 'package:flutter/material.dart';

/// Renders an initials badge for non-document objects.
/// Derives initials and a consistent color from the object type name,
/// so the same type always gets the same color across sessions and vaults.
///
/// Usage:
///   ObjectTypeBadge(objectTypeName: 'Contact', size: 28)
///   ObjectTypeBadge(objectTypeName: obj.objectTypeName, size: 28)
class ObjectTypeBadge extends StatelessWidget {
  final String objectTypeName;
  final double size;

  const ObjectTypeBadge({
    super.key,
    required this.objectTypeName,
    this.size = 28,
  });

  // ─── Initials ─────────────────────────────────────────────────────────────

  static String _initials(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';

    // Split on spaces, hyphens, underscores
    final words = trimmed
        .split(RegExp(r'[\s\-_]+'))
        .where((w) => w.isNotEmpty)
        .toList();

    if (words.length == 1) {
      // Single word: take up to 2 chars
      final w = words.first;
      return w.length == 1
          ? w.toUpperCase()
          : '${w[0]}${w[1]}'.toUpperCase();
    }

    // Multiple words: first letter of first two words
    return '${words[0][0]}${words[1][0]}'.toUpperCase();
  }

  // ─── Color palette ────────────────────────────────────────────────────────
  // 12 distinct, professional colors — assigned by hashing the type name
  // so the same name always maps to the same color.

  static const List<_ColorPair> _palette = [
    _ColorPair(Color(0xFF1565C0), Color(0xFF0D47A1)), // deep blue
    _ColorPair(Color(0xFF2E7D32), Color(0xFF1B5E20)), // deep green
    _ColorPair(Color(0xFF6A1B9A), Color(0xFF4A148C)), // deep purple
    _ColorPair(Color(0xFFC62828), Color(0xFFB71C1C)), // deep red
    _ColorPair(Color(0xFF00838F), Color(0xFF006064)), // deep cyan
    _ColorPair(Color(0xFFE65100), Color(0xFFBF360C)), // deep orange
    _ColorPair(Color(0xFF4527A0), Color(0xFF311B92)), // deep indigo
    _ColorPair(Color(0xFF558B2F), Color(0xFF33691E)), // deep light green
    _ColorPair(Color(0xFF00695C), Color(0xFF004D40)), // deep teal
    _ColorPair(Color(0xFF283593), Color(0xFF1A237E)), // deep indigo-blue
    _ColorPair(Color(0xFF6D4C41), Color(0xFF4E342E)), // deep brown
    _ColorPair(Color(0xFF37474F), Color(0xFF263238)), // deep blue-grey
  ];

  static _ColorPair _colorFor(String name) {
    if (name.trim().isEmpty) return _palette.last;
    // Simple djb2-style hash for consistency
    int hash = 5381;
    for (final c in name.toLowerCase().codeUnits) {
      hash = ((hash << 5) + hash) + c;
      hash = hash & 0x7FFFFFFF; // keep positive
    }
    return _palette[hash % _palette.length];
  }

  @override
  Widget build(BuildContext context) {
    final initials = _initials(objectTypeName);
    final colors = _colorFor(objectTypeName);

    // Font size scales with badge size; shorter initials get bigger text
    final double fontSize = initials.length == 1
        ? size * 0.42
        : size * 0.32;

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RoundedSquarePainter(colors: colors),
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              color: Colors.white,
              fontSize: fontSize,
              fontWeight: FontWeight.w800,
              height: 1.0,
              letterSpacing: initials.length > 1 ? -0.5 : 0,
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────
// Draws a rounded square with a subtle gradient and inner shadow,
// visually consistent with the FileTypeBadge shape language.

class _RoundedSquarePainter extends CustomPainter {
  final _ColorPair colors;
  const _RoundedSquarePainter({required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w * 0.22;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(radius),
    );

    // ── Body gradient ─────────────────────────────────────────────────────
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [colors.top, colors.bottom],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawRRect(rrect, bodyPaint);

    // ── Subtle inner shadow at top ────────────────────────────────────────
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.black.withOpacity(0.18),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.4));

    canvas.drawRRect(rrect, shadowPaint);

    // ── Subtle highlight at bottom-right ──────────────────────────────────
    final highlightPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.bottomRight,
        end: Alignment.center,
        colors: [
          Colors.white.withOpacity(0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    canvas.drawRRect(rrect, highlightPaint);
  }

  @override
  bool shouldRepaint(_RoundedSquarePainter old) => old.colors != colors;
}

// ─── Data class ──────────────────────────────────────────────────────────────

class _ColorPair {
  final Color top;
  final Color bottom;
  const _ColorPair(this.top, this.bottom);

  @override
  bool operator ==(Object other) =>
      other is _ColorPair && other.top == top && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(top, bottom);
}