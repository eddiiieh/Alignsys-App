import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../models/view_object.dart';

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
  bool _detailsExpanded = true;

  // propId -> edited vm
  final Map<int, _PropVm> _dirty = {};

  // Optional: show friendly datatype labels instead of MFDataType*
  // If you want to hide types completely, just return '' in _friendlyDatatype().
  static const Map<String, String> _datatypeLabel = {
    'MFDataTypeText': 'Text',
    'MFDataTypeInteger': 'Number',
    'MFDataTypeFloating': 'Decimal',
    'MFDataTypeBoolean': 'Yes/No',
    'MFDataTypeDate': 'Date',
    'MFDataTypeTime': 'Time',
    'MFDataTypeTimestamp': 'Date & time',
    'MFDataTypeLookup': 'Lookup',
    'MFDataTypeMultiSelectLookup': 'Multi-select',
  };

  String _friendlyDatatype(String raw) {
    // return '' to hide datatype completely
    return _datatypeLabel[raw] ?? '';
  }

  // NOTE: To eliminate "Property 100" dynamically for all object types,
  // the backend MUST include property names (e.g., "propertyName") in the response.
  // If it doesn't, there is no way to know the label without an extra "definitions" endpoint.
  String _friendlyPropLabel(_PropVm p) {
    final n = p.name.trim();
    final isFallback = n.startsWith('Property ');
    if (!isFallback && n.isNotEmpty) return n;

    // Fallback: still show something readable (no "Property 100" plain)
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
      // Prefer these keys in this order (handles {id: 31, title: Car} -> Car)
      for (final key in const [
        'displayValue',
        'title',
        'name',
        'caption',
        'text',
        'label',
      ]) {
        final x = v[key];
        if (x is String && x.trim().isNotEmpty) return x;
        if (x is num || x is bool) return x.toString();
      }

      // Common wrapper: { value: ... }
      if (v.containsKey('value')) return _valueToText(v['value']);

      // Last resort: make a compact string without curly-brace dump
      if (v.containsKey('id')) return 'ID ${v['id']}';
      return '';
    }

    return v.toString();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = _loadProps();
  }

  Future<List<_PropVm>> _loadProps() async {

    debugPrint('OPEN obj.id=${widget.obj.id}, classId=${widget.obj.classId}, title=${widget.obj.title}');
    
    final svc = context.read<MFilesService>();
    final raw = await svc.fetchObjectViewProps(
      objectId: widget.obj.id,
      classId: widget.obj.classId,
    );

    // IMPORTANT:
    // If your backend does NOT return property names, you'll still get Property (id) fallbacks.
    // Real fix: backend should include propertyName/title for each prop OR expose a definitions endpoint.
    return raw.map(_PropVm.fromJsonLoose).toList();
  }

  Future<void> _save(List<_PropVm> current) async {
    if (_saving) return;
    if (_dirty.isEmpty) return;

    setState(() => _saving = true);
    try {
      final svc = context.read<MFilesService>();

      final payloadProps = _dirty.values.map((p) {
        return {
          "id": p.id,
          // NOTE: This is still string-based updates. Lookup/multiselect/date/bool will need typed editors later.
          "value": p.editedValue ?? p.value ?? "",
          "datatype": p.datatype,
        };
      }).toList();

      await svc.updateObjectProps(
        objectId: widget.obj.id,
        objectTypeId: widget.obj.objectTypeId,
        classId: widget.obj.classId,
        props: payloadProps,
      );

      _dirty.clear();
      setState(() {
        _editMode = false;
        _future = _loadProps();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    return dt.toLocal().toString();
  }

  @override
  Widget build(BuildContext context) {
    final obj = widget.obj;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Text(obj.title, maxLines: 1, overflow: TextOverflow.ellipsis),
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
                _detailsCard(obj), // dropdown
                const SizedBox(height: 12),
                _metadataCard(props),
                const SizedBox(height: 12),
                _previewCardPlaceholder(obj),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _headerCard(ViewObject obj) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  obj.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${obj.classTypeName} • ID ${obj.displayId} • v${obj.versionId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _detailsCard(ViewObject obj) {
    return Container(
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: _detailsExpanded,
          onExpansionChanged: (v) => setState(() => _detailsExpanded = v),
          title: const Text('Details', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
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
    final rawCurrent = _dirty[p.id]?.editedValue ?? p.value;
    final currentText = _valueToText(rawCurrent);

    final label = _friendlyPropLabel(p);
    final typeLabel = _friendlyDatatype(p.datatype); // '' => hidden

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        enabled: _editMode,
        initialValue: currentText,
        decoration: InputDecoration(
          labelText: label,
          helperText: typeLabel.isEmpty ? null : typeLabel, // hides MFDataType* noise
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
  final int id; // property id for UpdateObjectProps.props[].id
  final String name;
  final String datatype;
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

  // Loose parser because GetObjectViewProps field names may vary.
  static _PropVm fromJsonLoose(Map<String, dynamic> m) {
    final id = (m['id'] as num?)?.toInt() ??
        (m['propId'] as num?)?.toInt() ??
        (m['propertyId'] as num?)?.toInt() ??
        0;

    final name = (m['name'] as String?) ??
        (m['propertyName'] as String?) ??
        (m['title'] as String?) ??
        'Property $id';

    final datatype = (m['datatype'] as String?) ??
        (m['dataType'] as String?) ??
        (m['propertytype'] as String?) ??
        'string';

    final value = m.containsKey('value') ? m['value'] : (m['displayValue'] ?? '');

    return _PropVm(id: id, name: name, datatype: datatype, value: value);
  }
}
