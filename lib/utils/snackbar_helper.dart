import 'package:flutter/material.dart';
import 'package:mfiles_app/utils/error_messages.dart';

class SnackbarHelper {
  static void showSuccess(
    BuildContext context,
    String message, {
    Color color = Colors.green,
    IconData icon = Icons.check_circle_outline,
    Duration duration = const Duration(seconds: 3),
  }) =>
      _show(context, message, color, icon, duration);

  /// Accepts a String OR an exception object. Always sanitised.
  static void showError(
    BuildContext context,
    Object error, {
    Duration duration = const Duration(seconds: 5),
  }) =>
      _show(context, _clean(error), Colors.red.shade700,
          Icons.error_outline, duration);

  static void showWarning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 5),
  }) =>
      _show(context, message, const Color(0xFFD97706),
          Icons.warning_amber_outlined, duration);

  // ── internals ────────────────────────────────────────────────────────────

  static final _technical = RegExp(
    r'Exception|error:|\[\d{3}\]|Socket|Timeout|Format|type \x27|null|http|DSS|[{}]',
    caseSensitive: false,
  );

  static String _clean(Object e) {
    final s = e
        .toString()
        .replaceFirst(RegExp(r'^(Exception|Error):\s*'), '')
        .trim();
    if (s.isEmpty) return 'Something went wrong. Please try again.';
    return _technical.hasMatch(s) ? humanizeError(s) : s;
  }

  static void _show(
    BuildContext context,
    String message,
    Color color,
    IconData icon,
    Duration duration,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          backgroundColor: color,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          margin: const EdgeInsets.all(12),
          duration: duration,
          showCloseIcon: true,
          closeIconColor: Colors.white70,
        ),
      );
  }
}