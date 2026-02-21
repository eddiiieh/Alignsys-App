import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:photo_view/photo_view.dart';
import 'package:open_filex/open_filex.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';

class DocumentPreviewScreen extends StatefulWidget {
  final int displayObjectId;
  final int classId;
  final int fileId;
  final String fileTitle;
  final String extension;
  final String reportGuid;

  const DocumentPreviewScreen({
    super.key,
    required this.displayObjectId,
    required this.classId,
    required this.fileId,
    required this.fileTitle,
    required this.extension,
    required this.reportGuid,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  late Future<File> _fileFuture;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _fileFuture = _downloadFile();
  }

  String _cleanExt(String ext) => ext.trim().toLowerCase().replaceFirst('.', '');


  Future<File> _downloadFile() async {
    final svc = context.read<MFilesService>();

    final extToUse = _cleanExt(widget.extension); // always keep original extension

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

  Future<void> _openExternally(File file) async {
    try {
      final result = await OpenFilex.open(file.path);
      if (result.type != ResultType.done) {
        throw Exception(result.message);
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

  Widget _buildPreview(File file) {
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
        backgroundDecoration: BoxDecoration(color: Colors.grey.shade50),
        loadingBuilder: (context, event) => Center(
          child: CircularProgressIndicator(
            value: event == null
                ? 0
                : event.cumulativeBytesLoaded / (event.expectedTotalBytes ?? 1),
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
            return _buildUnsupportedPreview(
              'Error reading file: ${snap.error}',
              file: file,
            );
          }

          return SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: SelectableText(
              snap.data ?? '',
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 13,
              ),
            ),
          );
        },
      );
    }

    // Not previewable -> push user to open externally
    return _buildUnsupportedPreview(
      'Preview not available for .$ext files.\n\nUse "Open Externally" to view this file.',
      file: file,
    );
  }

  Widget _buildUnsupportedPreview(String message, {required File file}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.visibility_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => _openExternally(file),
              icon: const Icon(Icons.open_in_new),
              label: const Text('Open Externally'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bannerExt = widget.extension.isEmpty ? '' : '.${_cleanExt(widget.extension)}';

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        title: Text(
          widget.fileTitle.isEmpty ? 'File ${widget.fileId}' : widget.fileTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            onPressed: _downloading ? null : _downloadToDevice,
            icon: _downloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.download),
            tooltip: 'Download',
          ),
          FutureBuilder<File>(
            future: _fileFuture,
            builder: (context, snap) {
              return IconButton(
                onPressed: snap.hasData ? () => _openExternally(snap.data!) : null,
                icon: const Icon(Icons.open_in_new),
                tooltip: 'Open Externally',
              );
            },
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: Colors.white,
            child: Row(
              children: [
                Icon(Icons.insert_drive_file, size: 16, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${widget.fileTitle}$bannerExt',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: FutureBuilder<File>(
              future: _fileFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.error_outline, size: 64, color: Colors.red.shade300),
                          const SizedBox(height: 16),
                          Text(
                            'Failed to load file',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.red.shade700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            snap.error.toString(),
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final file = snap.data!;
                _cleanExt(file.path.split('.').last);

                // Optional: if you want to AUTO-open external for non-previewables, uncomment:
                // if (!_canPreview(ext)) {
                //   WidgetsBinding.instance.addPostFrameCallback((_) => _openExternally(file));
                // }

                return _buildPreview(file);
              },
            ),
          ),
        ],
      ),
    );
  }
}