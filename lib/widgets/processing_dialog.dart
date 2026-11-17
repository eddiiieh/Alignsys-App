import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ProcessingDialog extends StatefulWidget {
  final String operation;
  const ProcessingDialog({super.key, required this.operation});

  @override
  State<ProcessingDialog> createState() => _ProcessingDialogState();
}

class _ProcessingDialogState extends State<ProcessingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String get _processingTitle {
    final t = widget.operation.toLowerCase();
    if (t.contains("checking in"))  return "Checking In";
    if (t.contains("checking out")) return "Checking Out";
    if (t.contains("delete"))       return "Deleting Objects";
    if (t.contains("download"))     return "Downloading";
    if (t.contains("upload"))       return "Uploading";
    if (t.contains("convert"))      return "Converting to PDF";
    return "Processing";
  }

  String get _processingMessage {
    final t = widget.operation.toLowerCase();
    if (t.contains("checking in"))  return "Please wait while the selected documents are being checked in.";
    if (t.contains("checking out")) return "Please wait while the selected documents are being checked out.";
    if (t.contains("delete"))       return "Please wait while the selected documents are being deleted.";
    if (t.contains("download"))     return "Preparing your documents...";
    if (t.contains("upload"))       return "Uploading your documents...";
    if (t.contains("convert"))      return "Converting documents to PDF...";
    return widget.operation;
  }

  IconData get _processingIcon {
    final t = widget.operation.toLowerCase();
    if (t.contains("checking in"))  return Icons.lock_open_rounded;
    if (t.contains("checking out")) return Icons.lock_rounded;
    if (t.contains("delete"))       return Icons.delete_outline_rounded;
    if (t.contains("download"))     return Icons.download_rounded;
    if (t.contains("upload"))       return Icons.upload_rounded;
    if (t.contains("convert"))      return Icons.picture_as_pdf_rounded;
    return Icons.sync_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final isDelete = widget.operation.toLowerCase().contains("delete");

    return Dialog(
      backgroundColor: c.surfaceElevated,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: isDelete ? c.dangerSurface : c.brandTint,
                shape: BoxShape.circle,
              ),
              child: Icon(
                _processingIcon,
                size: 28,
                color: isDelete ? c.dangerText : c.brand,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _processingTitle,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: c.brand,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _processingMessage,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: c.textSecondary),
            ),
            const SizedBox(height: 20),
            _AnimatedDots(controller: _controller),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDots extends AnimatedWidget {
  const _AnimatedDots({required AnimationController controller})
      : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final t = (listenable as AnimationController).value;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final opacity = ((t * 3 - i) % 3 / 2).clamp(0.2, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Opacity(
            opacity: opacity,
            child: CircleAvatar(radius: 5, backgroundColor: c.brand),
          ),
        );
      }),
    );
  }
}

Future<void> showProcessingDialog({
  required BuildContext context,
  required String operation,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => ProcessingDialog(operation: operation),
  );
}