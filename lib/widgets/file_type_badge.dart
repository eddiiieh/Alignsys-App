import 'package:flutter/material.dart';

/// Renders a Microsoft-style document icon with a colored letter badge.
///
/// Image file types (jpg, jpeg, png, gif, webp, bmp, svg) render as a
/// flat image placeholder icon — light rounded square with two blue mountains
/// and a circle sun, matching the standard image-file visual language.
///
/// Usage:
///   FileTypeBadge(extension: 'pdf', size: 44)
class FileTypeBadge extends StatelessWidget {
  final String extension;
  final double size;

  const FileTypeBadge({
    super.key,
    required this.extension,
    this.size = 44,
  });

  // ─── Image extension detector ─────────────────────────────────────────────

  static bool _isImage(String ext) {
    const imageExts = {'jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'svg'};
    return imageExts.contains(ext.trim().toLowerCase());
  }

  // ─── Style data ───────────────────────────────────────────────────────────

  static _BadgeStyle _styleFor(String ext) {
    switch (ext.trim().toLowerCase()) {
      case 'pdf':
        return const _BadgeStyle(
          label: 'PDF',
          topColor: Color(0xFFCC2222),
          bottomColor: Color(0xFFA01818),
          labelColor: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        );

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

      case 'one':
        return const _BadgeStyle(
          label: 'N',
          topColor: Color(0xFF7B2FAE),
          bottomColor: Color(0xFF5E2190),
          labelColor: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        );

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
    // ── Image files: flat image placeholder icon ───────────────────────────────
    if (_isImage(extension)) {
      return SizedBox(
        width: size,
        height: size,
        child: CustomPaint(
          painter: _FlatImageIconPainter(),
        ),
      );
    }

    // ── All other file types: document-page badge ─────────────────────────────
    final style = _styleFor(extension);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _DocumentPagePainter(style: style),
        child: Center(
          child: Padding(
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

// ─── Flat Image Icon Painter ──────────────────────────────────────────────────
// Matches the reference: light blue-grey rounded square background,
// two flat triangular mountains in blue, circle sun between the peaks.

class _FlatImageIconPainter extends CustomPainter {
  const _FlatImageIconPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final radius = w * 0.18;

    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, w, h),
      Radius.circular(radius),
    );

    // ── Background: light blue-grey ───────────────────────────────────────────
    final bgPaint = Paint()..color = const Color(0xFFDFE9F7);
    canvas.drawRRect(rrect, bgPaint);

    // Clip to rounded square
    canvas.clipRRect(rrect);

    // ── Far mountain (right, smaller, darker blue) ────────────────────────────
    final farMtnPaint = Paint()..color = const Color(0xFF5B8DEF);
    final farMtnPath = Path()
      ..moveTo(w * 0.40, h * 1.02)
      ..lineTo(w * 0.70, h * 0.38)
      ..lineTo(w * 1.02, h * 1.02)
      ..close();
    canvas.drawPath(farMtnPath, farMtnPaint);

    // ── Near mountain (left, larger, lighter blue) ────────────────────────────
    final nearMtnPaint = Paint()..color = const Color(0xFF7AAAF5);
    final nearMtnPath = Path()
      ..moveTo(-w * 0.02, h * 1.02)
      ..lineTo(w * 0.37, h * 0.32)
      ..lineTo(w * 0.76, h * 1.02)
      ..close();
    canvas.drawPath(nearMtnPath, nearMtnPaint);

    // ── Sun circle ────────────────────────────────────────────────────────────
    final sunPaint = Paint()..color = const Color(0xFF5B8DEF);
    canvas.drawCircle(
      Offset(w * 0.67, h * 0.28),
      w * 0.13,
      sunPaint,
    );
  }

  @override
  bool shouldRepaint(_FlatImageIconPainter old) => false;
}

// ─── Document Page Painter ────────────────────────────────────────────────────

class _DocumentPagePainter extends CustomPainter {
  final _BadgeStyle style;
  const _DocumentPagePainter({required this.style});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    const foldRatio = 0.28;
    final fold = w * foldRatio;
    final radius = w * 0.10;

    final bodyPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [style.topColor, style.bottomColor],
      ).createShader(Rect.fromLTWH(0, 0, w, h));

    final bodyPath = Path()
      ..moveTo(radius, 0)
      ..lineTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w, h - radius)
      ..quadraticBezierTo(w, h, w - radius, h)
      ..lineTo(radius, h)
      ..quadraticBezierTo(0, h, 0, h - radius)
      ..lineTo(0, radius)
      ..quadraticBezierTo(0, 0, radius, 0)
      ..close();

    canvas.drawPath(bodyPath, bodyPaint);

    final foldPaint = Paint()..color = Colors.white.withOpacity(0.18);
    final foldPath = Path()
      ..moveTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w - fold, fold)
      ..close();
    canvas.drawPath(foldPath, foldPaint);

    final creasePaint = Paint()
      ..color = Colors.white.withOpacity(0.30)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(w - fold, 0), Offset(w - fold, fold), creasePaint);
    canvas.drawLine(Offset(w - fold, fold), Offset(w, fold), creasePaint);

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