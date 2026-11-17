import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ErrorDialog extends StatelessWidget {
  final String title;
  final String message;
  final VoidCallback? onRetry;

  const ErrorDialog({
    super.key,
    required this.title,
    required this.message,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AlertDialog(
      backgroundColor: c.surfaceElevated,
      title: Row(
        children: [
          Icon(Icons.error_outline, color: c.dangerText),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title,
              style: TextStyle(color: c.textPrimary),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(color: c.textSecondary),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'OK',
            style: TextStyle(color: c.textSecondary),
          ),
        ),
        if (onRetry != null)
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              onRetry!();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: c.brand,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
      ],
    );
  }

  static void show(
    BuildContext context,
    String title,
    String message, {
    VoidCallback? onRetry,
  }) {
    showDialog(
      context: context,
      builder: (context) => ErrorDialog(
        title: title,
        message: message,
        onRetry: onRetry,
      ),
    );
  }
}