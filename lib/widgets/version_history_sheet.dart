import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/document_preview_screen.dart';
import 'package:provider/provider.dart';

import '../models/object_version.dart';
import '../models/view_object.dart';
import '../services/mfiles_service.dart';
import '../theme/app_colors.dart';
import '../utils/snackbar_helper.dart';
import 'processing_dialog.dart';

Future<void> showVersionHistorySheet(
  BuildContext context, {
  required ViewObject obj,
  VoidCallback? onRolledBack,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _VersionHistorySheet(obj: obj, onRolledBack: onRolledBack),
  );
}

class _VersionHistorySheet extends StatefulWidget {
  final ViewObject obj;
  final VoidCallback? onRolledBack;

  const _VersionHistorySheet({required this.obj, this.onRolledBack});

  @override
  State<_VersionHistorySheet> createState() => _VersionHistorySheetState();
}

class _VersionHistorySheetState extends State<_VersionHistorySheet> {
  late Future<List<ObjectVersion>> _future;
  final Set<int> _openingVersionIds = {};
  bool _rollingBack = false;

  int get _displayObjectId =>
      int.tryParse(widget.obj.displayId) ?? widget.obj.id;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<ObjectVersion>> _load() {
    final svc = context.read<MFilesService>();
    return svc.fetchObjectVersions(
      displayObjectId: _displayObjectId,
      classId: widget.obj.classId,
    );
  }

  Future<void> _previewVersion(ObjectVersion v) async {
  final file = v.firstFile;
  if (file == null) return;

  final ext = file.extension.trim().toLowerCase().replaceFirst('.', '');

  if (ext == 'pdf') {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentPreviewScreen(
          displayObjectId: _displayObjectId,
          classId: widget.obj.classId,
          fileId: file.fileId,
          objectTypeId: widget.obj.objectTypeId,
          fileTitle: file.fileTitle,
          extension: file.extension,
          reportGuid: file.reportGuid ?? '',
          versionId: v.versionId,
          canDownload: false,
        ),
      ),
    );
  } else {
    await _openVersion(v);   // non-PDF: existing external-open flow
  }
}

  Future<void> _openVersion(ObjectVersion version) async {
    final file = version.firstFile;
    if (file == null) {
      SnackbarHelper.showError(context, 'No file attached to this version.');
      return;
    }

    setState(() => _openingVersionIds.add(version.versionId));
    try {
      final svc = context.read<MFilesService>();
      await svc.downloadAndOpenObjectVersionFile(
        displayObjectId: _displayObjectId,
        versionId: version.versionId,
        fileId: file.fileId,
        classId: widget.obj.classId,
        fileTitle: file.fileTitle,
        extension: file.extension,
      );
    } catch (e) {
      if (!mounted) return;
      SnackbarHelper.showError(context, 'Could not open this version: $e');
    } finally {
      if (mounted) {
        setState(() => _openingVersionIds.remove(version.versionId));
      }
    }
  }

  Future<void> _rollback(ObjectVersion version) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RollbackConfirmDialog(version: version),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _rollingBack = true);

    // Show the processing indicator on top of the sheet while the
    // rollback request is in flight.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          const ProcessingDialog(operation: 'Rolling back document'),
    );

    try {
      final svc = context.read<MFilesService>();
      final ok = await svc.rollbackToVersion(
        objectId: _displayObjectId,
        classId: widget.obj.classId,
        versionId: version.versionId,
      );

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close processing dialog

      if (ok) {
        SnackbarHelper.showSuccess(
            context, 'Rolled back to version ${version.versionId}');
        widget.onRolledBack?.call();
        Navigator.pop(context); // close the sheet
      } else {
        SnackbarHelper.showError(context, svc.error ?? 'Rollback failed');
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        SnackbarHelper.showError(context, 'Rollback failed: $e');
      }
    } finally {
      if (mounted) setState(() => _rollingBack = false);
    }
  }

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      expand: false,
      builder:
          (context, scrollController) => Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Version History',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w600,
                                color: AppColors.primary,
                                letterSpacing: 0.1,
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.1),
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: Icon(
                                    context.read<MFilesService>().iconForViewObject(widget.obj),
                                    color: AppColors.primary,
                                    size: 17,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    widget.obj.title,
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.grey.shade900,
                                      height: 1.25,
                                    ),
                                    maxLines: 4,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.close, color: Colors.grey.shade500),
                        onPressed: () => Navigator.pop(context),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: Colors.grey.shade100),
                Expanded(
                  child: FutureBuilder<List<ObjectVersion>>(
                    future: _future,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      if (snap.hasError) {
                        return Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              'Could not load version history: ${snap.error}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }

                      final versions = snap.data ?? [];
                      if (versions.isEmpty) {
                        return Center(
                          child: Text(
                            'No version history available',
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 13,
                            ),
                          ),
                        );
                      }

                      final currentVersionId = versions
                          .map((v) => v.versionId)
                          .reduce((a, b) => a > b ? a : b);

                      return Material(
                        type: MaterialType.transparency,
                        child: ListView.separated(
                          controller: scrollController,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: versions.length,
                          separatorBuilder:
                              (_, __) => Divider(
                                height: 1,
                                color: Colors.grey.shade100,
                              ),
                          itemBuilder: (context, index) {
                            final v = versions[index];
                            final isCurrent = v.versionId == currentVersionId;
                            final isOpening = _openingVersionIds.contains(
                              v.versionId,
                            );
                            final dt = v.lastModifiedUtcParsed;
                            final dateStr =
                                dt != null
                                    ? '${dt.day}/${dt.month}/${dt.year} • ${_formatTime(dt)}'
                                    : v.lastModifiedUtc;

                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              enabled: !_rollingBack,
                              leading: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color:
                                      isCurrent
                                          ? AppColors.primary.withOpacity(0.12)
                                          : Colors.grey.shade100,
                                  shape: BoxShape.circle,
                                ),
                                child: Center(
                                  child:
                                      isOpening
                                          ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                          : Text(
                                            'v${v.versionId}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w700,
                                              color:
                                                  isCurrent
                                                      ? AppColors.primary
                                                      : Colors.grey.shade600,
                                            ),
                                          ),
                                ),
                              ),
                              title: Row(
                                children: [
                                  Text(
                                    'Version ${v.versionId}',
                                    style: const TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (isCurrent) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withOpacity(
                                          0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Current',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              subtitle: Text(
                                '$dateStr • ${v.lastModifiedBy}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500,
                                ),
                              ),
                              onTap: isOpening ? null : () => _previewVersion(v),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (v.firstFile != null)
                                    IconButton(
                                      icon: const Icon(Icons.visibility_outlined,
                                          size: 20, color: AppColors.primary),
                                      tooltip: 'Preview',
                                      onPressed: isOpening ? null : () => _previewVersion(v),
                                    ),
                                  if (!isCurrent)
                                    IconButton(
                                      icon: Icon(Icons.settings_backup_restore_rounded,
                                          size: 20, color: Colors.grey.shade500),
                                      tooltip: 'Rollback to this version',
                                      onPressed: _rollingBack ? null : () => _rollback(v),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Confirmation dialog for rolling back to a version, styled to match
/// [_ActionDialog] in delete_object_helper.dart (icon circle, title,
/// subtitle, Cancel/Confirm button row).
class _RollbackConfirmDialog extends StatelessWidget {
  final ObjectVersion version;

  const _RollbackConfirmDialog({required this.version});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.settings_backup_restore_rounded,
                size: 28, color: AppColors.primary),
          ),
          const SizedBox(height: 12),
          const Text(
            'Rollback Version',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Version ${version.versionId}',
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
          Text(
            'This will replace the current version. This action cannot be undone.',
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
                onPressed: () => Navigator.pop(context, false),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.grey.shade700,
                  side: BorderSide(color: Colors.grey.shade300),
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Cancel', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text('Rollback', style: TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ],
    );
  }
}