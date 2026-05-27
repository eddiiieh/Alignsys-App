// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../widgets/network_banner.dart';
import '../services/mfiles_service.dart';
import '../theme/app_colors.dart';

class DocumentPreviewScreen extends StatefulWidget {
  final int displayObjectId;
  final int classId;
  final int fileId;
  final int objectTypeId;
  final String fileTitle;
  final String extension;
  final String reportGuid;
  final bool canDownload;

  const DocumentPreviewScreen({
    super.key,
    required this.displayObjectId,
    required this.classId,
    required this.fileId,
    required this.objectTypeId,
    required this.fileTitle,
    required this.extension,
    required this.reportGuid,
    this.canDownload = false,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

// CHANGED: mixin WidgetsBindingObserver so we can detect app-resume after
// the user returns from the external viewer app.
class _DocumentPreviewScreenState extends State<DocumentPreviewScreen>
    with WidgetsBindingObserver {
  late Future<File> _fileFuture;
  bool _downloading = false;

  // CHANGED: tracks whether we have already handed the file off to an
  // external app.  When true, _buildPreview shows a "Opened externally"
  // card instead of the stuck spinner.
  bool _openedExternally = false;

  @override
  void initState() {
    super.initState();
    _fileFuture = _downloadFile();
    // CHANGED: register for app lifecycle events
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // CHANGED: always unregister the observer
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // CHANGED: when the user comes back from the external app the OS resumes
  // our Flutter app.  We reset _openedExternally so the screen no longer
  // looks "stuck" — it now shows the confirmation card with an "Open again"
  // button instead of the spinner.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedExternally) {
      if (mounted) {
        setState(() {
          // Keep _openedExternally = true so the card stays visible.
          // The card has an "Open again" button, which is better UX than
          // silently reverting to a spinner.
        });
      }
    }
  }

  String _cleanExt(String ext) =>
      ext.trim().toLowerCase().replaceFirst('.', '');

  Future<File> _downloadFile() async {
    final svc = context.read<MFilesService>();

    // ── Cache hit: return immediately ────────────────────────────────
    final cached = svc.cachedFile(widget.fileId);
    if (cached != null && await cached.exists()) {
      debugPrint('📦 File cache hit for fileId=${widget.fileId}');
      // CHANGED: store reference for the "Open again" button
      return cached;
    }

    debugPrint('📥 File cache miss for fileId=${widget.fileId}, downloading…');

    final extToUse = _cleanExt(widget.extension);

    final result = await svc.downloadFileBytesWithFallback(
      displayObjectId: widget.displayObjectId,
      classId: widget.classId,
      fileId: widget.fileId,
      reportGuid: widget.reportGuid,
      expectedExtension: extToUse,
    );

    final filename = _safeFilename(widget.fileTitle, extToUse, widget.fileId);
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';

    final file = File(filePath);
    await file.writeAsBytes(result.bytes, flush: true);

    // ── Store in cache ────────────────────────────────────────────────
    svc.cacheFile(widget.fileId, file);

    // CHANGED: store reference
    return file;
  }

  String _safeFilename(String title, String ext, int fileId) {
    var safe = title.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_').trim();
    if (safe.isEmpty) safe = 'file_$fileId';
    final cleanExt = _cleanExt(ext);
    if (cleanExt.isEmpty) return safe;
    if (safe.toLowerCase().endsWith('.$cleanExt')) return safe;
    return '$safe.$cleanExt';
  }

  Future<void> _downloadToDevice() async {
    setState(() => _downloading = true);
    try {
      final svc = context.read<MFilesService>();
      final savedPath = await svc.downloadAndSaveFile(
        displayObjectId: widget.displayObjectId,
        classId: widget.classId,
        fileId: widget.fileId,
        fileTitle: widget.fileTitle,
        extension: widget.extension,
        reportGuid: widget.reportGuid,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded to: $savedPath'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 3),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Download failed: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // CHANGED: _openExternally now sets _openedExternally = true on success,
  // which replaces the spinner with the confirmation card immediately.
  Future<void> _openExternally(File file) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
      }
      // CHANGED: mark as handed off — triggers rebuild to show the card
      if (mounted) {
        setState(() => _openedExternally = true);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Open failed: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  // CHANGED: new widget shown after a file has been successfully handed off
  // to an external app.  Replaces the stuck "Opening file…" spinner.
  Widget _buildOpenedExternallyCard(File file) {
    final ext = _cleanExt(file.path.split('.').last).toUpperCase();
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.open_in_new_rounded,
                size: 52,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Opened in external app',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              ext.isNotEmpty
                  ? 'This $ext file was opened in another app on your device.'
                  : 'This file was opened in another app on your device.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 24),
            // "Open again" — re-triggers the external app
            FilledButton.icon(
              onPressed: () => _openExternally(file),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open again'),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 12),
            // "Go back" — clean exit
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Go back'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
                side: BorderSide(color: Colors.grey.shade300),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(File file) {
    // CHANGED: if we've already handed off to an external app, show the
    // confirmation card immediately — no more stuck spinner on back-nav.
    if (_openedExternally) {
      return _buildOpenedExternallyCard(file);
    }

    final ext = _cleanExt(file.path.split('.').last);

    if (ext == 'pdf') {
      return SfPdfViewer.file(
        file,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        enableDoubleTapZooming: true,
      );
    }

    if (['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'].contains(ext)) {
      return PhotoView(
        imageProvider: FileImage(file),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        backgroundDecoration:
            BoxDecoration(color: AppColors.surfaceLight),
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(
            value: event == null
                ? 0
                : event.cumulativeBytesLoaded /
                    (event.expectedTotalBytes ?? 1),
          ),
        ),
      );
    }

    if (['txt', 'json', 'xml', 'csv', 'log', 'md'].contains(ext)) {
      return FutureBuilder<String>(
        future: file.readAsString(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            WidgetsBinding.instance
                .addPostFrameCallback((_) => _openExternally(file));
            return const Center(child: CircularProgressIndicator());
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              snap.data ?? '',
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
            ),
          );
        },
      );
    }

    // CHANGED: unsupported format — hand off to OS.
    // The postFrameCallback triggers _openExternally, which will flip
    // _openedExternally = true and cause a rebuild to show the card.
    // The spinner shown here is therefore only ever visible for the brief
    // moment before the external app picker/launcher appears.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _openExternally(file));
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            'Opening file…',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
          ),
          const SizedBox(height: 8),
          // CHANGED: small hint so the user isn't confused if the OS picker
          // takes a moment to appear
          Text(
            'Launching external app',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bannerExt = widget.extension.isEmpty
        ? ''
        : '.${_cleanExt(widget.extension)}';

    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.fileTitle.isEmpty
              ? 'File ${widget.fileId}'
              : widget.fileTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          if (widget.canDownload)
            IconButton(
              onPressed: _downloading ? null : _downloadToDevice,
              icon: _downloading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.download),
              tooltip: 'Download',
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: NetworkBanner(
        child: Column(
          children: [
            // ── File info banner ───────────────────────────────────────
            FutureBuilder<File>(
              future: _fileFuture,
              builder: (context, snap) {
                final fileReady = snap.hasData;
                return Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Icon(Icons.insert_drive_file,
                          size: 16, color: Colors.grey.shade500),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.fileTitle}$bannerExt',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Open externally',
                        child: InkWell(
                          // CHANGED: when already opened externally, tapping
                          // "Open" again re-triggers the external app rather
                          // than doing nothing.
                          onTap: fileReady
                              ? () => _openExternally(snap.data!)
                              : null,
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: fileReady
                                  ? AppColors.primary.withOpacity(0.08)
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: fileReady
                                    ? AppColors.primary.withOpacity(0.2)
                                    : Colors.grey.shade200,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.open_in_new,
                                  size: 14,
                                  color: fileReady
                                      ? AppColors.primary
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Open',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: fileReady
                                        ? AppColors.primary
                                        : Colors.grey.shade400,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const Divider(height: 1),

            // ── Preview area ───────────────────────────────────────────
            Expanded(
              child: FutureBuilder<File>(
                future: _fileFuture,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  if (snap.hasError) {
                    final svc = context.read<MFilesService>();
                    final isTrashed = svc.isObjectDeleted(widget.displayObjectId);
                    final errStr = snap.error.toString().toLowerCase();
                    final isCommitError = errStr.contains('not been committed') ||
                        errStr.contains('not committed');
                    final isCorruptError = errStr.contains('could not find') ||
                        errStr.contains('file signature') ||
                        errStr.contains('corrupted');

                    final icon = isTrashed
                        ? Icons.delete_outline_rounded
                        : isCommitError
                            ? Icons.lock_clock_outlined
                            : isCorruptError
                                ? Icons.broken_image_outlined
                                : Icons.cloud_off_rounded;

                    final color = isTrashed
                        ? Colors.red.shade400
                        : isCommitError
                            ? Colors.orange.shade400
                            : isCorruptError
                                ? Colors.purple.shade300
                                : Colors.grey.shade400;

                    final title = isTrashed
                        ? 'Document has been trashed'
                        : isCommitError
                            ? 'File not checked in'
                            : isCorruptError
                                ? 'File may be corrupted'
                                : 'Could not load file';

                    final message = isTrashed
                        ? 'This document was moved to trash. Restore it in the Trash tab to preview it again.'
                        : isCommitError
                            ? 'This file has not been checked in to M-Files yet. Ask the owner to check it in and try again.'
                            : isCorruptError
                                ? 'The file could not be read. It may be damaged or in an unsupported format.'
                                : 'The file could not be downloaded. The file could be trashed.';

                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(32),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(20),
                              decoration: BoxDecoration(
                                color: color.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(icon, size: 52, color: color),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              title,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.grey.shade800,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              message,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                                height: 1.5,
                              ),
                            ),
                            if (isTrashed) ...[
                              const SizedBox(height: 24),
                              OutlinedButton.icon(
                                onPressed: () => Navigator.pop(context),
                                icon: const Icon(Icons.arrow_back_rounded, size: 16),
                                label: const Text('Go Back'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.red.shade600,
                                  side: BorderSide(color: Colors.red.shade300),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  }

                  return _buildPreview(snap.data!);
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}