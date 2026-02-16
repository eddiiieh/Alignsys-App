import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/view_object.dart';
import '../models/object_file.dart';
import '../services/mfiles_service.dart';
import '../utils/file_icon_resolver.dart';
import '../screens/document_preview_screen.dart';

class ObjectInfoDropdown extends StatefulWidget {
  final ViewObject obj;

  const ObjectInfoDropdown({super.key, required this.obj});

  @override
  State<ObjectInfoDropdown> createState() => _ObjectInfoDropdownState();
}

class _ObjectInfoDropdownState extends State<ObjectInfoDropdown> {
  late Future<Map<String, dynamic>> _infoFuture;
  bool _downloading = false;

  final Map<int, String> _propNameById = {};
  final Set<int> _allowedMetaPropIds = {};
  static const Set<int> _excludeMetaPropIds = {100};

  @override
  void initState() {
    super.initState();
    _infoFuture = _loadInfo();
  }

  Future<Map<String, dynamic>> _loadInfo() async {
    final svc = context.read<MFilesService>();

    await svc.fetchClassProperties(widget.obj.objectTypeId, widget.obj.classId);

    _allowedMetaPropIds
      ..clear()
      ..addAll(
        svc.classProperties.where((p) => !p.isHidden && !p.isAutomatic).map((p) => p.id),
      )
      ..add(0)
      ..removeAll(_excludeMetaPropIds);

    _propNameById
      ..clear()
      ..addAll({0: 'Name or title', 100: 'Class'})
      ..addEntries(svc.classProperties.map((p) => MapEntry(p.id, p.title)));

    final propsRaw = await svc.fetchObjectViewProps(
      objectId: widget.obj.id,
      classId: widget.obj.classId,
    );

    for (final m in propsRaw) {
      final int? id = (m['id'] as num?)?.toInt() ??
          (m['propId'] as num?)?.toInt() ??
          (m['propertyId'] as num?)?.toInt();
      if (id == null) continue;

      final candidate = (m['propName'] as String?) ??
          (m['propertyName'] as String?) ??
          (m['name'] as String?) ??
          (m['title'] as String?);

      if (candidate == null) continue;
      final trimmed = candidate.trim();
      if (trimmed.isEmpty || trimmed.startsWith('Property ')) continue;

      _propNameById[id] = trimmed;
    }

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
    return dt.toLocal().toString().split('.')[0];
  }

  String _friendlyPropLabel(Map<String, dynamic> prop) {
    final int? id = (prop['id'] as num?)?.toInt() ??
        (prop['propId'] as num?)?.toInt() ??
        (prop['propertyId'] as num?)?.toInt();

    if (id == null) return 'Property';

    final mapped = _propNameById[id];
    if (mapped != null && mapped.trim().isNotEmpty) return mapped;

    final name = (prop['propName'] as String?) ??
        (prop['name'] as String?) ??
        (prop['propertyName'] as String?) ??
        '';
    final n = name.trim();
    final isFallback = n.startsWith('Property ');
    if (!isFallback && n.isNotEmpty) return n;

    return 'Property ($id)';
  }

  String _extractValue(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    if (value is num || value is bool) return value.toString();

    if (value is List) {
      return value
          .map(_extractValue)
          .where((s) => s.trim().isNotEmpty)
          .join(', ');
    }

    if (value is Map) {
      for (final key in ['displayValue', 'title', 'name', 'caption', 'text', 'label']) {
        final x = value[key];
        if (x is String && x.trim().isNotEmpty) return x;
        if (x is num || x is bool) return x.toString();
      }
      if (value.containsKey('value')) return _extractValue(value['value']);
      if (value.containsKey('id')) return 'ID ${value['id']}';
      return '';
    }

    return value.toString();
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

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.85,
              maxWidth: MediaQuery.of(context).size.width * 0.95,
            ),
            child: Stack(
              children: [
                DocumentPreviewScreen(
                  displayObjectId: displayIdInt,
                  classId: widget.obj.classId,
                  fileId: file.fileId,
                  fileTitle: file.fileTitle,
                  extension: file.extension,
                  reportGuid: file.reportGuid,
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: Material(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      borderRadius: BorderRadius.circular(20),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.close, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _infoFuture,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        if (snap.hasError) {
          return Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              'Error loading info: ${snap.error}',
              style: TextStyle(color: Colors.red.shade700, fontSize: 12),
            ),
          );
        }

        final data = snap.data!;
        final propsRaw = data['props'] as List;
        final files = data['files'] as List<ObjectFile>;

        final metaProps = propsRaw.where((prop) {
          final int? id = (prop['id'] as num?)?.toInt() ??
              (prop['propId'] as num?)?.toInt() ??
              (prop['propertyId'] as num?)?.toInt();
          return id != null && _allowedMetaPropIds.contains(id);
        }).toList();

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Basic Information (with Title as first field)
              _buildSectionTitle('Basic Information'),
              const SizedBox(height: 8),
              _buildInfoRow('Title', widget.obj.title),
              _buildInfoRow('Class', widget.obj.classTypeName),
              _buildInfoRow('Modified', _formatDate(widget.obj.lastModifiedUtc)),

              const SizedBox(height: 12),
              Divider(height: 1, color: Colors.grey.shade300),
              const SizedBox(height: 12),

              // Metadata
              _buildSectionTitle('Metadata'),
              const SizedBox(height: 8),
              if (metaProps.isEmpty)
                Text(
                  'No metadata available',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                )
              else
                ...metaProps.map((prop) {
                  final name = _friendlyPropLabel(prop);
                  final value = _extractValue(prop['value']);
                  return _buildInfoRow(name, value);
                }),

              if (files.isNotEmpty) ...[
                const SizedBox(height: 12),
                Divider(height: 1, color: Colors.grey.shade300),
                const SizedBox(height: 12),

                _buildSectionTitle('Preview Files (${files.length})'),
                const SizedBox(height: 8),
                ...files.map((file) => _buildFileRow(file)),
              ],
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
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: Color(0xFF072F5F),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(ObjectFile file) {
    final ext = file.extension.isEmpty ? '' : '.${file.extension}';
    final icon = FileIconResolver.iconForExtension(file.extension);

    return InkWell(
      onTap: _downloading ? null : () => _previewFile(file),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: const Color(0xFF072F5F)),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    file.fileTitle.isEmpty ? 'File ${file.fileId}' : file.fileTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'v${file.fileVersion}${ext.isEmpty ? '' : ' • $ext'}',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (_downloading)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              PopupMenuButton<String>(
                padding: EdgeInsets.zero,
                icon: Icon(
                  Icons.more_vert,
                  size: 16,
                  color: Colors.grey.shade600,
                ),
                tooltip: 'More options',
                onSelected: (action) async {
                  if (action == 'open') {
                    await _openFile(file);
                  } else if (action == 'download') {
                    await _downloadFile(file);
                  }
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(
                    value: 'open',
                    child: Row(
                      children: [
                        Icon(Icons.open_in_new, size: 16),
                        SizedBox(width: 12),
                        Text('Open Externally'),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'download',
                    child: Row(
                      children: [
                        Icon(Icons.download, size: 16),
                        SizedBox(width: 12),
                        Text('Download'),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}