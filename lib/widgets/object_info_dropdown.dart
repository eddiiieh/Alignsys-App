import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/view_object.dart';
import '../services/mfiles_service.dart';
import '../theme/app_colors.dart';

class ObjectInfoDropdown extends StatefulWidget {
  final ViewObject obj;
  final bool isDeleted;

  const ObjectInfoDropdown({
    super.key,
    required this.obj,
    this.isDeleted = false,
  });

  @override
  State<ObjectInfoDropdown> createState() => _ObjectInfoDropdownState();
}

class _ObjectInfoDropdownState extends State<ObjectInfoDropdown> {
  Future<Map<String, dynamic>>? _infoFuture;

  final Map<int, String> _propNameById = {};

  static const Set<int> _excludePropIds = {20, 21, 23, 25, 38, 100};

  bool _showAllProps = false;
  static const int _initialPropCount = 10;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _infoFuture = _loadInfo();
      setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant ObjectInfoDropdown oldWidget) {
    super.didUpdateWidget(oldWidget);
    final o = oldWidget.obj;
    final n = widget.obj;
    final meaningfullyChanged = o.id != n.id ||
        o.classId != n.classId ||
        o.objectTypeId != n.objectTypeId ||
        o.versionId != n.versionId;

    if (meaningfullyChanged) {
      _showAllProps = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _infoFuture = _loadInfo();
        setState(() {});
      });
    }
  }

  Future<Map<String, dynamic>> _loadInfo() async {
    final svc = context.read<MFilesService>();

    try {
      await svc.fetchClassProperties(
          widget.obj.objectTypeId, widget.obj.classId);
      _propNameById
        ..clear()
        ..addAll({0: 'Name or title', 100: 'Class'})
        ..addEntries(svc.classProperties.map((p) => MapEntry(p.id, p.title)));
    } catch (_) {
      _propNameById
        ..clear()
        ..addAll({0: 'Name or title', 100: 'Class'});
    }

    final displayIdInt =
        int.tryParse(widget.obj.displayId) ?? widget.obj.id;

    final propsRaw = await svc.fetchObjectViewProps(
      objectId: displayIdInt,
      objectTypeId: widget.obj.objectTypeId,
    ).timeout(const Duration(seconds: 15), onTimeout: () => []);

    for (final m in propsRaw) {
      final int? id = _extractId(m);
      if (id == null) continue;
      if (!_propNameById.containsKey(id) ||
          _propNameById[id]!.startsWith('Property ')) {
        final candidate = _firstName(m);
        if (candidate != null) _propNameById[id] = candidate;
      }
    }

    return {'props': propsRaw};
  }

  // ── helpers ──────────────────────────────────────────────────────────────

  int? _extractId(Map<String, dynamic> m) {
    final v = m['id'] ?? m['propId'] ?? m['propertyId'];
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
    return null;
  }

  String? _firstName(Map<String, dynamic> m) {
    for (final key in ['propName', 'name', 'propertyName', 'title']) {
      final v = m[key];
      if (v is String) {
        final s = v.trim();
        if (s.isNotEmpty && !s.startsWith('Property ')) return s;
      }
    }
    return null;
  }

  String _friendlyPropLabel(Map<String, dynamic> prop) {
    final int? id = _extractId(prop);
    if (id != null) {
      final mapped = _propNameById[id];
      if (mapped != null && mapped.trim().isNotEmpty) return mapped;
    }
    final fallback = _firstName(prop);
    if (fallback != null) return fallback;
    return id != null ? 'Property ($id)' : 'Property';
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
      for (final key in [
        'displayValue',
        'title',
        'name',
        'caption',
        'text',
        'label'
      ]) {
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

  String _formatDate(DateTime? dt) {
    if (dt == null) return '-';
    return dt.toLocal().toString().split('.')[0];
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final future = _infoFuture;
    if (future == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
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

        final propsRaw = (snap.data!['props'] as List);

        final metaProps = propsRaw.where((prop) {
          final int? id = _extractId(prop as Map<String, dynamic>);
          if (id == null) return false;
          if (_excludePropIds.contains(id)) return false;
          final val = _extractValue(prop['value']);
          return val.trim().isNotEmpty;
        }).toList();

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEyebrow('Basic Information'),
              const SizedBox(height: 6),
              _buildInfoRow('Title', widget.obj.title),
              _buildInfoRow('Class', widget.obj.classTypeName),
              _buildInfoRow('Created', _formatDate(widget.obj.createdUtc)),

              const SizedBox(height: 16),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 16),

              _buildEyebrow('Metadata'),
              const SizedBox(height: 6),
              if (metaProps.isEmpty)
                Text(
                  'No metadata available',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                )
              else ...[
                ...(_showAllProps
                        ? metaProps
                        : metaProps.take(_initialPropCount).toList())
                    .map((prop) {
                  final name =
                      _friendlyPropLabel(prop as Map<String, dynamic>);
                  final value = _extractValue(prop['value']);
                  return _buildInfoRow(name, value);
                }),

                if (metaProps.length > _initialPropCount) ...[
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showAllProps = !_showAllProps),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _showAllProps
                                ? Icons.keyboard_arrow_up_rounded
                                : Icons.keyboard_arrow_down_rounded,
                            size: 16,
                            color: Colors.grey.shade600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showAllProps
                                ? 'Show less'
                                : 'Show ${metaProps.length - _initialPropCount} more',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildEyebrow(String title) {
    return Text(
      title.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: AppColors.primary,
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
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
                color: Color(0xFF1A1A1A),
              ),
            ),
          ),
        ],
      ),
    );
  }
}