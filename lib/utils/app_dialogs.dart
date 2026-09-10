import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Standard info/blocking dialog used across the app in place of ad-hoc
/// SnackBars for anything the user actually needs to read — empty states,
/// permission denials, blocked actions. Mirrors the "Signing already in
/// progress" dialog: rounded corners, bold title, grey body copy, single
/// primary-colored action button.
Future<void> showAppInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
  IconData? icon,
  Color? iconColor,
  String buttonText = 'Got it',
}) {
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.primary).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor ?? AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5, height: 1.4),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          onPressed: () => Navigator.pop(ctx),
          child: Text(buttonText),
        ),
      ],
    ),
  );
}

/// Two-action variant of showAppInfoDialog, for cases where dismissing
/// isn't the useful path — e.g. a permission denial that needs a deep
/// link into Settings. Returns true if the user tapped the primary action.
Future<bool> showAppActionDialog(
  BuildContext context, {
  required String title,
  required String message,
  required String actionText,
  IconData? icon,
  Color? iconColor,
  String cancelText = 'Not Now',
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          if (icon != null) ...[
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.primary).withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor ?? AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: TextStyle(color: Colors.grey.shade700, fontSize: 13.5, height: 1.4),
      ),
      actions: [
        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.grey.shade600),
          onPressed: () => Navigator.pop(ctx, false),
          child: Text(cancelText),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(actionText),
        ),
      ],
    ),
  );
  return result ?? false;
}