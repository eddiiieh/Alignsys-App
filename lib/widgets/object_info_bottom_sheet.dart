import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/view_object.dart';
import '../models/object_file.dart';
import '../services/mfiles_service.dart';
import '../utils/file_icon_resolver.dart';
import '../screens/object_details_screen.dart';
import '../screens/document_preview_screen.dart';

class ObjectInfoBottomSheet extends StatefulWidget {
  final ViewObject obj;

  const ObjectInfoBottomSheet({super.key, required this.obj});

  @override
  State<ObjectInfoBottomSheet> createState() => _ObjectInfoBottomSheetState();
}

class _ObjectInfoBottomSheetState extends State<ObjectInfoBottomSheet> {
  late Future<Map<String, dynamic>> _infoFuture;
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _infoFuture = _loadInfo();
  }

  Future<Map<String, dynamic>> _loadInfo() async {
    final svc = context.read<MFilesService>();

    // Fetch metadata properties
    final propsRaw = await svc.fetchObjectViewProps(
      objectId: widget.obj.id,
      classId: widget.obj.classId,
    );

    // Fetch attached files
    final files = await svc.fetchObjectFiles(
      objectId: widget.obj.id,
      classId: widget.obj.classId,
    );

    return {
      'props': propsRaw,
      'files': files,
    };
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return dt.toLocal().toString().split('.')[0]; // Remove microseconds
  }

  Future<void> _previewFile(ObjectFile file) async {
    final displayIdInt = int.tryParse(widget.obj.displayId);
    if (displayIdInt == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid object display ID: ${widget.obj.displayId}'),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentPreviewScreen(
          displayObjectId: displayIdInt,
          classId: widget.obj.classId,
          fileId: file.fileId,
          fileTitle: file.fileTitle,
          extension: file.extension,
          reportGuid: file.reportGuid,
        ),
      ),
    );
  }

  Future<void> _openFile(ObjectFile file) async {
    final displayIdInt = int.tryParse(widget.obj.displayId);
    if (displayIdInt == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid object display ID: ${widget.obj.displayId}'),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    setState(() => _downloading = true);
    try {
      final svc = context.read<MFilesService>();
      await svc.downloadAndOpenFile(
        displayObjectId: displayIdInt,
        classId: widget.obj.classId,
        fileId: file.fileId,
        fileTitle: file.fileTitle,
        extension: file.extension,
        reportGuid: file.reportGuid,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Open failed: $e'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _downloadFile(ObjectFile file) async {
    final displayIdInt = int.tryParse(widget.obj.displayId);
    if (displayIdInt == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid object display ID: ${widget.obj.displayId}'),
          backgroundColor: Colors.red.shade600,
        ),
      );
      return;
    }

    setState(() => _downloading = true);
    try {
      final svc = context.read<MFilesService>();
      final savedPath = await svc.downloadAndSaveFile(
        displayObjectId: displayIdInt,
        classId: widget.obj.classId,
        fileId: file.fileId,
        fileTitle: file.fileTitle,
        extension: file.extension,
        reportGuid: file.reportGuid,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved to: $savedPath'),
          backgroundColor: Colors.green.shade600,
          duration: const Duration(seconds: 4),
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

  // ✅ IMPROVED: Match ObjectDetailsScreen's _valueToText logic
  String _extractValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();

    // Handle lists (e.g., multi-select lookups or arrays)
    if (value is List) {
      return value
          .map(_extractValue)
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
    }

    // Handle maps/objects - try common display keys
    if (value is Map) {
      for (final key in const [
        'displayValue',
        'title',
        'name',
        'caption',
        'text',
        'label'
      ]) {
        final v = value[key];
        if (v is String && v.trim().isNotEmpty) return v;
        if (v is num || v is bool) return v.toString();
      }
      
      // If there's a nested 'value' field, recurse
      if (value.containsKey('value')) {
        return _extractValue(value['value']);
      }
      
      // Last resort: show ID if available
      if (value.containsKey('id')) {
        return 'ID ${value['id']}';
      }
      
      return '';
    }

    return value.toString();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              // Handle bar
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade400,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.obj.title,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '${widget.obj.classTypeName} • ID ${widget.obj.displayId}',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Content
              Expanded(
                child: FutureBuilder<Map<String, dynamic>>(
                  future: _infoFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snap.hasError) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(
                            'Error loading info: ${snap.error}',
                            style: TextStyle(color: Colors.red.shade700),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      );
                    }

                    final data = snap.data!;
                    final propsRaw = data['props'] as List;
                    final files = data['files'] as List<ObjectFile>;

                    return ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.all(20),
                      children: [
                        // Basic Info Section
                        _buildSectionTitle('Basic Information'),
                        const SizedBox(height: 12),
                        _buildInfoCard([
                          _buildInfoRow('Object Type', widget.obj.objectTypeName),
                          _buildInfoRow('Class', widget.obj.classTypeName),
                          _buildInfoRow('Version', 'v${widget.obj.versionId}'),
                          _buildInfoRow('Created', _formatDate(widget.obj.createdUtc)),
                          _buildInfoRow('Modified', _formatDate(widget.obj.lastModifiedUtc)),
                        ]),

                        const SizedBox(height: 24),

                        // Metadata Section
                        _buildSectionTitle('Metadata'),
                        const SizedBox(height: 12),
                        _buildInfoCard(
                          propsRaw.take(5).map((prop) {
                            final name = (prop['propName'] ?? prop['name'] ?? 'Property').toString();
                            final value = _extractValue(prop['value']);
                            return _buildInfoRow(name, value);
                          }).toList(),
                        ),

                        const SizedBox(height: 24),

                        // Files Section
                        _buildSectionTitle('Attached Files (${files.length})'),
                        const SizedBox(height: 12),
                        if (files.isEmpty)
                          _buildEmptyFilesCard()
                        else
                          ...files.map((file) => _buildFileCard(file)),

                        const SizedBox(height: 24),

                        // "View Full Details" Button
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () {
                              Navigator.pop(context); // Close bottom sheet
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ObjectDetailsScreen(obj: widget.obj),
                                ),
                              );
                            },
                            icon: const Icon(Icons.open_in_full, size: 18),
                            label: const Text('View Full Details'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF072F5F),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                              elevation: 0,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        color: Color(0xFF072F5F),
      ),
    );
  }

  Widget _buildInfoCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: children,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileCard(ObjectFile file) {
    final ext = file.extension.isEmpty ? '' : '.${file.extension}';
    final icon = FileIconResolver.iconForExtension(file.extension);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ListTile(
        dense: true,
        leading: Icon(icon, color: const Color(0xFF072F5F)),
        title: Text(
          file.fileTitle.isEmpty ? 'File ${file.fileId}' : file.fileTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
        ),
        subtitle: Text(
          'v${file.fileVersion}${ext.isEmpty ? '' : ' • $ext'}',
          style: const TextStyle(fontSize: 12),
        ),
        trailing: _downloading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : PopupMenuButton<String>(
                icon: Icon(Icons.more_vert, size: 18, color: Colors.grey.shade600),
                onSelected: (action) async {
                  if (action == 'preview') {
                    await _previewFile(file);
                  } else if (action == 'open') {
                    await _openFile(file);
                  } else if (action == 'download') {
                    await _downloadFile(file);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'preview',
                    child: Row(
                      children: [
                        Icon(Icons.visibility, size: 18),
                        SizedBox(width: 12),
                        Text('Preview'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'open',
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new, size: 18),
                        SizedBox(width: 12),
                        Text('Open Externally'),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(Icons.download, size: 18),
                        SizedBox(width: 12),
                        Text('Download'),
                      ],
                    ),
                  ),
                ],
              ),
        onTap: _downloading ? null : () => _previewFile(file),
      ),
    );
  }

  Widget _buildEmptyFilesCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Icon(Icons.insert_drive_file_outlined, 
               size: 48, 
               color: Colors.grey.shade300),
          const SizedBox(height: 8),
          Text(
            'No files attached',
            style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
          ),
        ],
      ),
    );
  }
}