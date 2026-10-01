// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
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
  final int fileId;
  final int objectTypeId;
  final String fileTitle;
  final String extension;
  final String reportGuid;
  final bool canDownload;
  final int? versionId;
  final int classId;

  const DocumentPreviewScreen({
    super.key,
    required this.displayObjectId,
    required this.fileId,
    required this.objectTypeId,
    required this.fileTitle,
    required this.extension,
    required this.reportGuid,
    required this.classId,
    this.canDownload = false,
    this.versionId,
  });

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen>
    with WidgetsBindingObserver {
  late Future<File> _fileFuture;
  bool _downloading = false;

  final PdfViewerController _pdfController = PdfViewerController();
  int _totalPages = 0;

  bool _searchActive = false;
  final TextEditingController _searchInputController = TextEditingController();
  final FocusNode _searchFieldFocus = FocusNode();
  PdfTextSearchResult? _searchResult;

  bool _openedExternally = false;

  @override
  void initState() {
    super.initState();
    _fileFuture = _downloadFile();
    WidgetsBinding.instance.addObserver(this);
    _searchFieldFocus.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchResult?.clear();
    _searchInputController.dispose();
    _searchFieldFocus.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _openedExternally) {
      if (mounted) {
        setState(() {
          // Keep _openedExternally = true so the card stays visible.
        });
      }
    }
  }

  String _cleanExt(String ext) =>
      ext.trim().toLowerCase().replaceFirst('.', '');

  Future<File> _downloadFile() async {
    final svc = context.read<MFilesService>();

    if (widget.versionId != null) {
      debugPrint('📥 Fetching version ${widget.versionId} for fileId=${widget.fileId}');

      final result = await svc.fetchObjectFileVersion(
        displayObjectId: widget.displayObjectId,
        versionId: widget.versionId!,
        fileId: widget.fileId,
        objectTypeId: widget.objectTypeId,
        classId: widget.classId,
      );

      final extToUse = _cleanExt(widget.extension);
      final filename = _safeFilename(widget.fileTitle, extToUse, widget.fileId);
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$filename';

      final file = File(filePath);
      await file.writeAsBytes(result.bytes, flush: true);
      return file;
    }

    final cached = svc.cachedFile(widget.fileId);
    if (cached != null && await cached.exists()) {
      debugPrint('📦 File cache hit for fileId=${widget.fileId}');
      return cached;
    }

    debugPrint('📥 File cache miss for fileId=${widget.fileId}, downloading…');

    final extToUse = _cleanExt(widget.extension);

    final result = await svc.downloadFileBytesWithFallback(
      displayObjectId: widget.displayObjectId,
      fileId: widget.fileId,
      reportGuid: widget.reportGuid,
      expectedExtension: extToUse,
      classId: widget.classId,
    );

    final filename = _safeFilename(widget.fileTitle, extToUse, widget.fileId);
    final dir = await getTemporaryDirectory();
    final filePath = '${dir.path}/$filename';

    final file = File(filePath);
    await file.writeAsBytes(result.bytes, flush: true);

    svc.cacheFile(widget.fileId, file);

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

  void _toggleSearch() {
    setState(() {
      _searchActive = !_searchActive;
      if (!_searchActive) {
        _searchResult?.clear();
        _searchResult = null;
        _searchInputController.clear();
      }
    });
  }

  Widget _buildSearchNavButton({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: enabled ? AppColors.primary : Colors.grey.shade200,
            shape: BoxShape.circle,
          ),
          child: Icon(
            icon,
            size: 20,
            color: enabled ? Colors.white : Colors.grey.shade400,
          ),
        ),
      ),
    );
  }

  void _runSearch(String query) {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResult?.clear();
        _searchResult = null;
      });
      return;
    }
    final result = _pdfController.searchText(query.trim());
    result.addListener(() {
      if (mounted) setState(() {});
    });
    setState(() => _searchResult = result);
  }

  void _showJumpToPageSheet() {
    if (_totalPages <= 0) return;
    final controller = TextEditingController();
    final focusNode = FocusNode();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.keyboard_double_arrow_right_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Go to Page',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        'of $_totalPages',
                        style: const TextStyle(fontSize: 12, color: Colors.white70),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white70),
                        onPressed: () => Navigator.pop(sheetContext),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                TextField(
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1E293B),
                  ),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: Colors.grey.shade200),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 2,
                      ),
                    ),
                  ),
                  onSubmitted: (_) => _submitJumpToPage(sheetContext, controller.text),
                ),

                const SizedBox(height: 20),

                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(sheetContext),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey.shade700,
                          side: BorderSide(color: Colors.grey.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _submitJumpToPage(sheetContext, controller.text),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Go',
                          style: TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _submitJumpToPage(BuildContext sheetContext, String value) {
    final page = int.tryParse(value.trim());
    if (page == null || page < 1 || page > _totalPages) {
      ScaffoldMessenger.of(sheetContext).showSnackBar(
        SnackBar(content: Text('Enter a page between 1 and $_totalPages')),
      );
      return;
    }
    _pdfController.jumpToPage(page);
    Navigator.pop(sheetContext);
  }

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
            TextButton.icon(
              onPressed: () => _openExternally(file),
              icon: const Icon(Icons.open_in_new_rounded, size: 16),
              label: const Text('Open again'),
              style: TextButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18)),
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Go back'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.grey.shade700,
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
    if (_openedExternally) {
      return _buildOpenedExternallyCard(file);
    }

    final ext = _cleanExt(file.path.split('.').last);

    if (ext == 'pdf') {
      return SfPdfViewer.file(
        file,
        controller: _pdfController,
        canShowScrollHead: true,
        canShowScrollStatus: false,
        enableDoubleTapZooming: true,
        onDocumentLoaded: (details) {
          if (mounted) {
            setState(() => _totalPages = details.document.pages.count);
          }
        },
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
          if (_cleanExt(widget.extension) == 'pdf' && _totalPages > 0)
            IconButton(
              onPressed: _showJumpToPageSheet,
              icon: const Icon(Icons.keyboard_double_arrow_right_rounded),
              tooltip: 'Go to page',
            ),
          if (_cleanExt(widget.extension) == 'pdf')
            IconButton(
              onPressed: _toggleSearch,
              icon: Icon(_searchActive ? Icons.close : Icons.find_in_page_outlined),
              tooltip: _searchActive ? 'Close search' : 'Search text',
            ),
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
                      FileTypeBadge(
                        extension: _cleanExt(widget.extension),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${widget.fileTitle}$bannerExt',
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w500),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Tooltip(
                        message: 'Open externally',
                        child: InkWell(
                          onTap: fileReady
                              ? () => _openExternally(snap.data!)
                              : null,
                          borderRadius: BorderRadius.circular(20),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: fileReady
                                  ? AppColors.primary
                                  : Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.launch_rounded,
                                  size: 14,
                                  color: fileReady
                                      ? Colors.white
                                      : Colors.grey.shade400,
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  'Open',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: fileReady
                                        ? Colors.white
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

            if (_searchActive)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
                color: Colors.white,
                child: Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 44,
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(
                            color: _searchFieldFocus.hasFocus
                                ? AppColors.primary
                                : Colors.grey.shade200,
                            width: _searchFieldFocus.hasFocus ? 1.5 : 1,
                          ),
                        ),
                        child: TextField(
                          controller: _searchInputController,
                          focusNode: _searchFieldFocus,
                          autofocus: true,
                          textInputAction: TextInputAction.search,
                          style: const TextStyle(fontSize: 14),
                          decoration: InputDecoration(
                            hintText: 'Find in document',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade400,
                            ),
                            isDense: true,
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 11),
                            prefixIcon: Icon(
                              Icons.search,
                              size: 18,
                              color: _searchFieldFocus.hasFocus
                                  ? AppColors.primary
                                  : Colors.grey.shade400,
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 40,
                              minHeight: 36,
                            ),
                          ),
                          onSubmitted: _runSearch,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),

                    if (_searchResult != null && _searchResult!.hasResult)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          '${_searchResult!.currentInstanceIndex}/${_searchResult!.totalInstanceCount}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      )
                    else if (_searchResult != null && _searchResult!.isSearchCompleted)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Text(
                          'No results',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ),

                    const SizedBox(width: 8),

                    _buildSearchNavButton(
                      icon: Icons.keyboard_arrow_up,
                      tooltip: 'Previous match',
                      enabled: _searchResult?.hasResult ?? false,
                      onTap: () => setState(() => _searchResult!.previousInstance()),
                    ),
                    const SizedBox(width: 6),
                    _buildSearchNavButton(
                      icon: Icons.keyboard_arrow_down,
                      tooltip: 'Next match',
                      enabled: _searchResult?.hasResult ?? false,
                      onTap: () => setState(() => _searchResult!.nextInstance()),
                    ),
                  ],
                ),
              ),

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

                    // ── Existing error classifications ──
                    final isCommitError = errStr.contains('not been committed') ||
                        errStr.contains('not committed');

                    // ── NEW: checked-out detection ──
                    // M-Files error text for a checked-out file typically
                    // contains "checked out" or "is checked out".
                    final isCheckedOut = errStr.contains('checked out') ||
                        errStr.contains('checkedout') ||
                        errStr.contains('check out');

                    final isCorruptError = errStr.contains('could not find') ||
                        errStr.contains('file signature') ||
                        errStr.contains('corrupted');

                    // ── Icon ──
                    final icon = isTrashed
                        ? Icons.delete_outline_rounded
                        : isCheckedOut
                            ? Icons.lock_open_rounded
                            : isCommitError
                                ? Icons.lock_clock_outlined
                                : isCorruptError
                                    ? Icons.broken_image_outlined
                                    : Icons.cloud_off_rounded;

                    // ── Color ──
                    final color = isTrashed
                        ? Colors.red.shade400
                        : isCheckedOut
                            ? Colors.blue.shade400
                            : isCommitError
                                ? Colors.orange.shade400
                                : isCorruptError
                                    ? Colors.purple.shade300
                                    : Colors.grey.shade400;

                    // ── Title ──
                    final title = isTrashed
                        ? 'Document has been trashed'
                        : isCheckedOut
                            ? 'File is checked out'
                            : isCommitError
                                ? 'File not checked in'
                                : isCorruptError
                                    ? 'File may be corrupted'
                                    : 'Could not load file';

                    // ── Message ──
                    final message = isTrashed
                        ? 'This document was moved to trash. Restore it in the Trash tab to preview it again.'
                        : isCheckedOut
                            ? 'This file is currently checked out by another user. Ask them to check it in, then try again.'
                            : isCommitError
                                ? 'This file has not been checked in to M-Files yet. Ask the owner to check it in and try again.'
                                : isCorruptError
                                    ? 'The file could not be read. It may be damaged or in an unsupported format.'
                                    : 'The file could not be downloaded. The file could be checked out/trashed.';

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