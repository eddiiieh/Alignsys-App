// lib/utils/delete_object_helper.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../models/view_object.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PUBLIC API
// ─────────────────────────────────────────────────────────────────────────────

/// Whether an object row should show the long-press option.
/// Only requires a valid object id — classId may be 0 for documents.
bool canLongPress(ViewObject obj) => obj.id > 0;

/// Long-press → delete confirmation dialog.
Future<void> showLongPressDeleteSheet(
  BuildContext context, {
  required ViewObject obj,
  required VoidCallback onDeleted,
}) async {
  HapticFeedback.mediumImpact();
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ActionDialog(
      obj: obj,
      mode: _DialogMode.delete,
      onConfirmed: onDeleted,
    ),
  );
}

/// Long-press → restore confirmation dialog (for the Deleted tab).
Future<void> showLongPressRestoreSheet(
  BuildContext context, {
  required ViewObject obj,
  required VoidCallback onRestored,
}) async {
  HapticFeedback.mediumImpact();
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => _ActionDialog(
      obj: obj,
      mode: _DialogMode.restore,
      onConfirmed: onRestored,
    ),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// INTERNAL
// ─────────────────────────────────────────────────────────────────────────────

enum _DialogMode { delete, restore }

class _ActionDialog extends StatefulWidget {
  const _ActionDialog({
    required this.obj,
    required this.mode,
    required this.onConfirmed,
  });

  final ViewObject obj;
  final _DialogMode mode;
  final VoidCallback onConfirmed;

  @override
  State<_ActionDialog> createState() => _ActionDialogState();
}

class _ActionDialogState extends State<_ActionDialog> {
  bool _isBusy = false;

  bool get _isDelete => widget.mode == _DialogMode.delete;

  Future<void> _confirm() async {
    setState(() => _isBusy = true);
    final svc = context.read<MFilesService>();

    try {
      final bool success;

      if (_isDelete) {
        success = await svc.deleteObject(
          objectId: widget.obj.id,
          classId: widget.obj.classId,
        );
      } else {
        success = await svc.unDeleteObject(
          objectId: widget.obj.id,
          classId: widget.obj.classId,
        );
      }

      if (!mounted) return;

      Navigator.pop(context); // close dialog

      if (success) {
        widget.onConfirmed();
        final label = _isDelete ? 'deleted' : 'restored';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                Icon(
                  _isDelete ? Icons.check_circle_outline : Icons.restore,
                  color: Colors.white,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '"${widget.obj.title}" $label successfully',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            backgroundColor:
                _isDelete ? Colors.green.shade700 : Colors.blue.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      } else {
        final action = _isDelete ? 'Delete' : 'Restore';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$action failed. Please try again.'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      Navigator.pop(context);
      final action = _isDelete ? 'Delete' : 'Restore';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 20),
              const SizedBox(width: 10),
              Expanded(child: Text('$action failed: $e')),
            ],
          ),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
          margin: const EdgeInsets.all(12),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color iconBg =
        _isDelete ? Colors.red.shade50 : Colors.blue.shade50;
    final Color iconColor =
        _isDelete ? Colors.red.shade500 : Colors.blue.shade500;
    final IconData iconData =
        _isDelete ? Icons.delete_outline_rounded : Icons.restore_rounded;
    final String title = _isDelete ? 'Delete Object' : 'Restore Object';
    final String subtitle = _isDelete
        ? 'This action cannot be undone.'
        : 'The object will be moved back to its original location.';
    final Color confirmColor =
        _isDelete ? Colors.red.shade600 : Colors.blue.shade600;
    final String confirmLabel = _isDelete ? 'Delete' : 'Restore';

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Icon
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(iconData, size: 28, color: iconColor),
          ),
          const SizedBox(height: 12),

          // Title
          Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Object name
          Text(
            widget.obj.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),

          // Subtitle
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 4),
        ],
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _isBusy ? null : () => Navigator.pop(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: _isBusy ? null : _confirm,
                style: ElevatedButton.styleFrom(
                  backgroundColor: confirmColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: _isBusy
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : Text(confirmLabel,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}