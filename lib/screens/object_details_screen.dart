import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../models/view_object.dart';
import '../widgets/lookup_field.dart';

class ObjectDetailsScreen extends StatefulWidget {
  final ViewObject obj;

  const ObjectDetailsScreen({super.key, required this.obj});

  @override
  State<ObjectDetailsScreen> createState() => _ObjectDetailsScreenState();
}

class _ObjectDetailsScreenState extends State<ObjectDetailsScreen> {
  late Future<List<_PropVm>> _future;

  bool _editMode = false;
  bool _saving = false;

  // ✅ Header-card dropdown state
  bool _headerDetailsExpanded = false;

  // ✅ Local mutable title so UI reflects updates
  String _title = '';

  // propId -> friendly property title
  final Map<int, String> _propNameById = {};

  // ✅ Only these props appear in the Metadata card (same as create-form props)
  final Set<int> _allowedMetaPropIds = {};
  static const Set<int> _excludeMetaPropIds = {100};

  // propId -> edited vm
  final Map<int, _PropVm> _dirty = {};

  static const Map<String, String> _datatypeLabel = {
    'MFDatatypeText': 'Text',
    'MFDatatypeInteger': 'Number',
    'MFDatatypeFloating': 'Decimal',
    'MFDatatypeBoolean': 'Yes/No',
    'MFDatatypeDate': 'Date',
    'MFDatatypeTime': 'Time',
    'MFDatatypeTimestamp': 'Date & time',
    'MFDatatypeLookup': 'Lookup',
    'MFDatatypeMultiSelectLookup': 'Multi-select',
    'MFDatatypeMultiLineText': 'Multi-line',
  };

  String _friendlyDatatype(String raw) => _datatypeLabel[raw] ?? '';

  @override
  void initState() {
    super.initState();
    _title = widget.obj.title;
  }

  String _friendlyPropLabel(_PropVm p) {
    final mapped = _propNameById[p.id];
    if (mapped != null && mapped.trim().isNotEmpty) return mapped;

    final n = p.name.trim();
    final isFallback = n.startsWith('Property ');
    if (!isFallback && n.isNotEmpty) return n;

    return 'Property (${p.id})';
  }

  String _valueToText(dynamic v) {
    if (v == null) return '';
    if (v is String) return v;
    if (v is num || v is bool) return v.toString();

    if (v is List) {
      return v.map(_valueToText).where((s) => s.trim().isNotEmpty).join(', ');
    }

    if (v is Map) {
      for (final key in const ['displayValue', 'title', 'name', 'caption', 'text', 'label']) {
        final x = v[key];
        if (x is String && x.trim().isNotEmpty) return x;
        if (x is num || x is bool) return x.toString();
      }
      if (v.containsKey('value')) return _valueToText(v['value']);
      if (v.containsKey('id')) return 'ID ${v['id']}';
      return '';
    }

    return v.toString();
  }

  bool _isLookup(_PropVm p) => p.datatype == 'MFDatatypeLookup';
  bool _isMultiLookup(_PropVm p) => p.datatype == 'MFDatatypeMultiSelectLookup';

  List<int> _currentLookupIds(_PropVm p) {
    final edited = _dirty[p.id]?.editedValue;
    final source = edited ?? p.value;

    if (source is List) {
      final out = <int>[];
      for (final e in source) {
        if (e is Map && e['id'] != null) {
          final id = int.tryParse(e['id'].toString());
          if (id != null) out.add(id);
        } else if (e is int) {
          out.add(e);
        } else if (e is String) {
          final id = int.tryParse(e);
          if (id != null) out.add(id);
        }
      }
      return out;
    }

    if (source is int) return [source];
    if (source is List<int>) return source;

    if (source is String && source.contains(',')) {
      return source
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
    }

    final one = int.tryParse(source?.toString() ?? '');
    return one == null ? <int>[] : <int>[one];
  }

  String _lookupDisplayText(_PropVm p) {
    final source = _dirty[p.id]?.editedValue ?? p.value;

    if (source is List) {
      final titles = <String>[];
      for (final e in source) {
        if (e is Map) {
          final t = (e['title'] ?? e['name'] ?? e['displayValue'])?.toString();
          if (t != null && t.trim().isNotEmpty) titles.add(t.trim());
        } else {
          final t = e.toString().trim();
          if (t.isNotEmpty) titles.add(t);
        }
      }
      return titles.join(', ');
    }

    return _valueToText(source);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _loadProps();
  }

  void _scheduleTitleUpdate(String newTitle) {
    if (!mounted) return;
    if (newTitle.trim().isEmpty) return;
    if (newTitle == _title) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (newTitle == _title) return;
      setState(() => _title = newTitle);
    });
  }

  void _maybeUpdateTitleFromProps(List<_PropVm> vms) {
    final byId = {for (final p in vms) p.id: p};

    String? candidate;

    if (byId.containsKey(0)) {
      final t = _valueToText(byId[0]!.value).trim();
      if (t.isNotEmpty) candidate = t;
    }

    candidate ??= vms
        .where((p) => p.datatype == 'MFDatatypeText' || p.datatype == 'MFDatatypeMultiLineText')
        .map((p) => _valueToText(p.value).trim())
        .firstWhere((s) => s.isNotEmpty, orElse: () => '');

    if (candidate != null && candidate.trim().isNotEmpty) {
      _scheduleTitleUpdate(candidate);
    }
  }

  Future<List<_PropVm>> _loadProps() async {
    final svc = context.read<MFilesService>();

    await svc.fetchClassProperties(widget.obj.objectTypeId, widget.obj.classId);

    _allowedMetaPropIds
      ..clear()
      ..addAll(svc.classProperties.where((p) => !p.isHidden && !p.isAutomatic).map((p) => p.id))
      ..add(0)
      ..removeAll(_excludeMetaPropIds);

    _propNameById
      ..clear()
      ..addAll({0: 'Name or title', 100: 'Class'})
      ..addEntries(svc.classProperties.map((p) => MapEntry(p.id, p.title)));

    final raw = await svc.fetchObjectViewProps(
      objectId: widget.obj.id,
      classId: widget.obj.classId,
    );

    for (final m in raw) {
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

    final vms = raw.map(_PropVm.fromJsonLoose).toList();
    _maybeUpdateTitleFromProps(vms);

    return vms;
  }

  Future<void> _save(List<_PropVm> current) async {
    if (_saving) return;
    if (_dirty.isEmpty) return;

    setState(() => _saving = true);
    try {
      final svc = context.read<MFilesService>();

      final payloadProps = _dirty.values
          .where((p) => _allowedMetaPropIds.contains(p.id))
          .map((p) {
            dynamic v = p.editedValue ?? p.value ?? '';

            if (p.datatype == 'MFDatatypeLookup') {
              if (v is int) v = v.toString();
              if (v is List<int> && v.isNotEmpty) v = v.first.toString();
            } else if (p.datatype == 'MFDatatypeMultiSelectLookup') {
              if (v is List<int>) v = v.map((x) => x.toString()).join(',');
            }

            return {"id": p.id, "value": v.toString(), "datatype": p.datatype};
          })
          .toList();

      if (payloadProps.isEmpty) return;

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

      final ok = await svc.updateObjectProps(
        objectId: displayIdInt,
        objectTypeId: widget.obj.objectTypeId,
        classId: widget.obj.classId,
        props: payloadProps,
      );

      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: ${svc.error ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }

      _dirty.clear();
      if (!mounted) return;
      setState(() {
        _editMode = false;
        _future = _loadProps();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmt(DateTime? dt) => dt == null ? '-' : dt.toLocal().toString();

  @override
  Widget build(BuildContext context) {
    final obj = widget.obj;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Text(_title.isEmpty ? obj.title : _title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            onPressed: _saving
                ? null
                : () {
                    setState(() {
                      _editMode = !_editMode;
                      if (!_editMode) _dirty.clear();
                    });
                  },
            icon: Icon(_editMode ? Icons.close : Icons.edit),
          ),
          FutureBuilder<List<_PropVm>>(
            future: _future,
            builder: (context, snap) {
              final props = snap.data;
              final canSave = _editMode && !_saving && _dirty.isNotEmpty && props != null;

              return IconButton(
                onPressed: canSave ? () => _save(props!) : null,
                icon: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Icon(Icons.check),
              );
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: FutureBuilder<List<_PropVm>>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('Error: ${snap.error}'));
          }

          final props = snap.data ?? [];
          final metaProps = props.where((p) => _allowedMetaPropIds.contains(p.id)).toList();

          return RefreshIndicator(
            onRefresh: () async {
              setState(() {
                _future = _loadProps();
                _dirty.clear();
                _editMode = false;
              });
              await _future;
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: [
                _headerCard(obj),
                const SizedBox(height: 12),
                _metadataCard(metaProps),
                const SizedBox(height: 12),
                _previewCardPlaceholder(obj),
              ],
            ),
          );
        },
      ),
    );
  }

  // ✅ Header card now owns the "Details" dropdown
  Widget _headerCard(ViewObject obj) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _title.isEmpty ? obj.title : _title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _headerDetailsExpanded = !_headerDetailsExpanded),
                icon: Icon(_headerDetailsExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              '${obj.classTypeName} • ID ${obj.displayId} • v${obj.versionId}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox.shrink(),
            secondChild: Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Column(
                children: [
                  _kv('Object ID', obj.id.toString()),
                  _kv('Object Type', obj.objectTypeName),
                  _kv('Class', obj.classTypeName),
                  _kv('Version', obj.versionId.toString()),
                  _kv('Created', _fmt(obj.createdUtc)),
                  _kv('Last modified', _fmt(obj.lastModifiedUtc)),
                ],
              ),
            ),
            crossFadeState:
                _headerDetailsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  Widget _metadataCard(List<_PropVm> props) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Metadata', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Text(
                _editMode ? 'Editing' : 'Read-only',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...props.map(_propField).toList(),
        ],
      ),
    );
  }

  Widget _propField(_PropVm p) {
    final label = _friendlyPropLabel(p);

    if (_isLookup(p) || _isMultiLookup(p)) {
      final isMulti = _isMultiLookup(p);
      final selectedIds = _currentLookupIds(p);
      final hasValue = selectedIds.isNotEmpty;

      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_editMode)
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: LookupField(
                    title: '', // ✅ no duplicate label
                    propertyId: p.id,
                    isMultiSelect: isMulti,
                    onSelected: (items) {
                      setState(() {
                        if (isMulti) {
                          final ids = items.map((x) => x.id).toList();
                          _dirty[p.id] = p.copyWith(editedValue: ids);
                        } else {
                          final id = items.isNotEmpty ? items.first.id : null;
                          if (id == null) {
                            _dirty.remove(p.id);
                          } else {
                            _dirty[p.id] = p.copyWith(editedValue: id);
                          }
                        }
                      });
                    },
                  ),
                ),
              )
            else
              TextFormField(
                enabled: false,
                initialValue: _lookupDisplayText(p),
                decoration: InputDecoration(
                  labelText: label,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  isDense: true,
                ),
              ),
            if (_editMode)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  hasValue ? (isMulti ? '${selectedIds.length} selected' : 'Selected') : 'Select',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
          ],
        ),
      );
    }

    final rawCurrent = _dirty[p.id]?.editedValue ?? p.value;
    final currentText = _valueToText(rawCurrent);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        enabled: _editMode,
        initialValue: currentText,
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          isDense: true,
        ),
        onChanged: (v) {
          if (!_editMode) return;

          setState(() {
            final originalText = _valueToText(p.value);
            if (v == originalText) {
              _dirty.remove(p.id);
            } else {
              _dirty[p.id] = p.copyWith(editedValue: v);
            }
          });
        },
      ),
    );
  }

  Widget _previewCardPlaceholder(ViewObject obj) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Preview', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Text(
            'Preview will be wired after file endpoints are integrated '
            '(GetObjectFiles + DownloadActualFile).',
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(k, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '-' : v,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _PropVm {
  final int id;
  final String name;
  final String datatype; // keep MFDatatype*
  final dynamic value;
  final dynamic editedValue;

  _PropVm({
    required this.id,
    required this.name,
    required this.datatype,
    required this.value,
    this.editedValue,
  });

  _PropVm copyWith({dynamic editedValue}) {
    return _PropVm(
      id: id,
      name: name,
      datatype: datatype,
      value: value,
      editedValue: editedValue,
    );
  }

  static _PropVm fromJsonLoose(Map<String, dynamic> m) {
    final id = (m['id'] as num?)?.toInt() ??
        (m['propId'] as num?)?.toInt() ??
        (m['propertyId'] as num?)?.toInt() ??
        0;

    final name = (m['propName'] as String?) ??
        (m['name'] as String?) ??
        (m['propertyName'] as String?) ??
        (m['title'] as String?) ??
        'Property $id';

    final rawDatatype = (m['datatype'] as String?) ??
        (m['dataType'] as String?) ??
        (m['propertytype'] as String?) ??
        'MFDatatypeText';

    final datatype = rawDatatype.replaceAll('MFDataType', 'MFDatatype');

    final value = m.containsKey('value') ? m['value'] : (m['displayValue'] ?? '');

    return _PropVm(id: id, name: name, datatype: datatype, value: value);
  }
}
