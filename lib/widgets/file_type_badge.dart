import 'package:flutter/material.dart';

/// Renders a Microsoft-style document icon with a colored letter badge,
/// matching the visual style in the reference screenshot.
///
/// Usage:
///   FileTypeBadge(extension: 'pdf', size: 44)
///   FileTypeBadge.fromObject(svc: svc, obj: obj, size: 44)
///   FileTypeBadge.fromContentItem(svc: svc, item: item, size: 44)
class FileTypeBadge extends StatelessWidget {
  final String extension; // e.g. 'pdf', 'docx', 'xlsx' — or empty/null for unknown
  final double size;

  const FileTypeBadge({
    super.key,
    required this.extension,
    this.size = 44,
  });

  // ─── Convenience constructors ──────────────────────────────────────────────

  /// Build directly from a ViewObject (mirrors how you call iconForViewObject).
  // Uncomment and import your types if you want to use these:
  //
  // factory FileTypeBadge.fromObject({
  //   required MFilesService svc,
  //   required ViewObject obj,
  //   double size = 44,
  // }) {
  //   final ext = svc.cachedExtensionForObject(obj.id) ?? '';
  //   return FileTypeBadge(extension: ext, size: size);
  // }
  //
  // factory FileTypeBadge.fromContentItem({
  //   required MFilesService svc,
  //   required ViewContentItem item,
  //   double size = 44,
  // }) {
  //   final ext = item.isObject ? (svc.cachedExtensionForObject(item.id) ?? '') : '';
  //   return FileTypeBadge(extension: ext, size: size);
  // }

  // ─── Style data ───────────────────────────────────────────────────────────

  static _BadgeStyle _styleFor(String ext) {
    switch (ext.trim().toLowerCase()) {
      // PDF
      case 'pdf':
        return const _BadgeStyle(
          label: 'PDF',
          topColor: Color(0xFFCC2222),
          bottomColor: Color(0xFFA01818),
          labelColor: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        );

      // Word
      case 'doc':
      case 'docx':
      case 'rtf':
      case 'odt':
        return const _BadgeStyle(
          label: 'W',
          topColor: Color(0xFF1B5EBE),
          bottomColor: Color(0xFF1447A0),
          labelColor: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        );

      // Excel
      case 'xls':
      case 'xlsx':
      case 'csv':
      case 'ods':
        return const _BadgeStyle(
          label: 'X',
          topColor: Color(0xFF1E7A45),
          bottomColor: Color(0xFF175E35),
          labelColor: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        );

      // PowerPoint
      case 'ppt':
      case 'pptx':
      case 'odp':
        return const _BadgeStyle(
          label: 'P',
          topColor: Color(0xFFCC4E18),
          bottomColor: Color(0xFFAA3C10),
          labelColor: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        );

      // OneNote
      case 'one':
        return const _BadgeStyle(
          label: 'N',
          topColor: Color(0xFF7B2FAE),
          bottomColor: Color(0xFF5E2190),
          labelColor: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        );

      // Text / Markdown
      case 'txt':
      case 'md':
      case 'log':
        return const _BadgeStyle(
          label: 'TXT',
          topColor: Color(0xFF607D8B),
          bottomColor: Color(0xFF455A64),
          labelColor: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        );

      // Images
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
      case 'webp':
      case 'bmp':
      case 'svg':
        return const _BadgeStyle(
          label: 'IMG',
          topColor: Color(0xFF7B2FAE),
          bottomColor: Color(0xFF5E2190),
          labelColor: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
        );

      // Archives
      case 'zip':
      case 'rar':
      case '7z':
      case 'tar':
      case 'gz':
        return const _BadgeStyle(
          label: 'ZIP',
          topColor: Color(0xFF6D4C41),
          bottomColor: Color(0xFF4E342E),
          labelColor: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        );

      // Audio
      case 'mp3':
      case 'wav':
      case 'aac':
      case 'm4a':
      case 'flac':
        return const _BadgeStyle(
          label: '♪',
          topColor: Color(0xFF0097A7),
          bottomColor: Color(0xFF00788A),
          labelColor: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w400,
        );

      // Video
      case 'mp4':
      case 'mkv':
      case 'mov':
      case 'avi':
      case 'webm':
        return const _BadgeStyle(
          label: '▶',
          topColor: Color(0xFFE64A19),
          bottomColor: Color(0xFFBF360C),
          labelColor: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w400,
        );

      // Unknown / folder-like
      default:
        return const _BadgeStyle(
          label: '?',
          topColor: Color(0xFF78909C),
          bottomColor: Color(0xFF546E7A),
          labelColor: Colors.white,
          fontSize: 16,
          fontWeight: FontWeight.w700,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _styleFor(extension);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DocumentPagePainter(style: style),
        child: Center(
          child: Padding(
            // Slight downward nudge so label sits in the body (below the folded corner)
            padding: EdgeInsets.only(top: size * 0.18),
            child: Text(
              style.label,
              style: TextStyle(
                color: style.labelColor,
                fontSize: style.fontSize * (size / 44),
                fontWeight: style.fontWeight,
                height: 1.0,
                letterSpacing: style.label.length > 1 ? -0.5 : 0,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Painter ─────────────────────────────────────────────────────────────────

class _DocumentPagePainter extends CustomPainter {
  final _BadgeStyle style;
  const _DocumentPagePainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // The fold triangle sits in the top-right corner
    const foldRatio = 0.28; // how big the fold corner is
    final fold = w * foldRatio;
    final radius = w * 0.10;

    // ── Body gradient (top to bottom) ────────────────────────────────────────
    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [style.topColor, style.bottomColor],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    // Page outline path (dog-ear top-right corner)
    final bodyPath = Path()
      ..moveTo(radius, 0)                     // top-left start (after radius)
      ..lineTo(w - fold, 0)                   // top edge → fold notch
      ..lineTo(w, fold)                       // diagonal cut down
      ..lineTo(w, h - radius)                 // right edge
      ..quadraticBezierTo(w, h, w - radius, h) // bottom-right radius
      ..lineTo(radius, h)                     // bottom edge
      ..quadraticBezierTo(0, h, 0, h - radius) // bottom-left radius
      ..lineTo(0, radius)                     // left edge
      ..quadraticBezierTo(0, 0, radius, 0)   // top-left radius
      ..close();

    canvas.drawPath(bodyPath, bodyPaint);

    // ── Fold triangle (slightly lighter) ─────────────────────────────────────
    final foldPaint = Paint()
      ..color = Colors.white.withOpacity(0.18);

    final foldPath = Path()
      ..moveTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w - fold, fold)
      ..close();

    canvas.drawPath(foldPath, foldPaint);

    // ── Fold crease line ──────────────────────────────────────────────────────
    final creasePaint = Paint()
      ..color = Colors.white.withOpacity(0.30)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;

    canvas.drawLine(Offset(w - fold, 0), Offset(w - fold, fold), creasePaint);
    canvas.drawLine(Offset(w - fold, fold), Offset(w, fold), creasePaint);

    // ── Subtle inner shadow at top (depth effect) ─────────────────────────────
    final shadowPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.center,
        colors: [
          Colors.black.withOpacity(0.15),
          Colors.transparent,
        ],
      ).createShader(Rect.fromLTWH(0, 0, w, h * 0.35));

    canvas.drawPath(bodyPath, shadowPaint);
  }

  @override
  bool shouldRepaint(_DocumentPagePainter old) => old.style != style;
}

// ─── Data class ──────────────────────────────────────────────────────────────

class _BadgeStyle {
  final String label;
  final Color topColor;
  final Color bottomColor;
  final Color labelColor;
  final double fontSize;
  final FontWeight fontWeight;

  const _BadgeStyle({
    required this.label,
    required this.topColor,
    required this.bottomColor,
    required this.labelColor,
    required this.fontSize,
    required this.fontWeight,
  });

  @override
  bool operator ==(Object other) =>
      other is _BadgeStyle && other.label == label && other.topColor == topColor;

  @override
  int get hashCode => Object.hash(label, topColor);
}