import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/mfiles_service.dart';
import '../models/view_object.dart';
import '../models/object_file.dart';
import '../models/object_comment.dart';
import '../widgets/lookup_field.dart';

class ObjectDetailsScreen extends StatefulWidget {
  final ViewObject obj;

  const ObjectDetailsScreen({super.key, required this.obj});

  @override
  State<ObjectDetailsScreen> createState() => _ObjectDetailsScreenState();
}

class _ObjectDetailsScreenState extends State<ObjectDetailsScreen> {
  late Future<List<_PropVm>> _future;
  late Future<List<ObjectFile>> _filesFuture;

  // Workflow
  late Future<WorkflowInfo?> _workflowFuture;
  int? _selectedNextStateId;
  bool _changingWorkflow = false;

  late Future<List<WorkflowOption>> _workflowsFuture;
  int? _selectedWorkflowId;
  bool _assigningWorkflow = false;

  bool _editMode = false;
  bool _saving = false;
  bool _downloading = false;

  bool _booted = false;
  bool _headerDetailsExpanded = false;

  String _title = '';

  final Map<int, String> _propNameById = {};
  final Set<int> _allowedMetaPropIds = {};
  static const Set<int> _excludeMetaPropIds = {100}; // Class
  final Map<int, _PropVm> _dirty = {};

  //Comments
  late Future<List<ObjectComment>> _commentsFuture;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _postingComment = false;

  @override
  void initState() {
    super.initState();
    _title = widget.obj.title;

    //Comments
    _commentsFuture = _loadComments();

    // ✅ Initialize futures immediately so build() never sees uninitialized late fields.
    _future = _loadProps();
    _filesFuture = _loadFiles();
    _workflowFuture = _loadWorkflow();
    _workflowsFuture = _loadWorkflowsForThisObject();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  int _initialStateForWorkflow(int workflowId) {
    const map = <int, int>{
      101: 101,
    };

    final v = map[workflowId];
    if (v == null) {
      throw Exception(
        'Initial state not configured for workflow $workflowId. '
        'Ask backend to expose initialStateId OR extend the map.',
      );
    }
    return v;
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
      ..addAll(
        svc.classProperties.where((p) => !p.isHidden && !p.isAutomatic).map((p) => p.id),
      )
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

  Future<List<ObjectFile>> _loadFiles() async {
    final svc = context.read<MFilesService>();
    return svc.fetchObjectFiles(objectId: widget.obj.id, classId: widget.obj.classId);
  }

  Future<WorkflowInfo?> _loadWorkflow() async {
    final svc = context.read<MFilesService>();

    final info = await svc.getObjectWorkflowState(
      objectTypeId: widget.obj.objectTypeId,
      objectId: widget.obj.id,
    );

    if (info == null) {
      _selectedNextStateId = null;
      return null;
    }

    if (mounted) {
      setState(() {
        _selectedNextStateId = info.nextStates.isNotEmpty ? info.nextStates.first.id : null;
      });
    }

    return info;
  }

  Widget _workflowCard(WorkflowInfo info) {
    final canChange = info.nextStates.isNotEmpty && !_changingWorkflow && !_saving && !_downloading;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Workflow', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (_changingWorkflow)
                const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          _kv('Name', info.workflowTitle),
          _kv('Current', info.currentStateTitle),
          if (info.assignmentDesc.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(info.assignmentDesc, style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ],
          const SizedBox(height: 10),
          if (info.nextStates.isEmpty)
            Text('No next steps available.', style: TextStyle(color: Colors.grey.shade600, fontSize: 12))
          else
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    value: _selectedNextStateId,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: 'Next state',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      isDense: true,
                    ),
                    items: info.nextStates
                        .map((s) => DropdownMenuItem<int>(
                              value: s.id,
                              child: Text(s.title, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: canChange ? (v) => setState(() => _selectedNextStateId = v) : null,
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: (!canChange || _selectedNextStateId == null)
                      ? null
                      : () async {
                          setState(() => _changingWorkflow = true);
                          try {
                            final svc = context.read<MFilesService>();
                            final ok = await svc.setObjectWorkflowState(
                              objectTypeId: widget.obj.objectTypeId,
                              objectId: widget.obj.id,
                              workflowId: info.workflowId,
                              stateId: _selectedNextStateId!,
                            );

                            if (!ok) {
                              if (!mounted) return;
                              final msg = svc.error ?? 'Unknown';
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Workflow update failed: $msg'),
                                  backgroundColor: Colors.red.shade600,
                                ),
                              );
                              return;
                            }

                            if (!mounted) return;
                            setState(() {
                              _workflowFuture = _loadWorkflow();
                              _future = _loadProps();
                            });
                          } finally {
                            if (mounted) setState(() => _changingWorkflow = false);
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF072F5F),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 0,
                  ),
                  child: const Text('Apply'),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<List<WorkflowOption>> _loadWorkflowsForThisObject() async {
    final svc = context.read<MFilesService>();
    return svc.fetchWorkflowsForObjectTypeClass(
      objectTypeId: widget.obj.objectTypeId,
      classTypeId: widget.obj.classId,
    );
  }

  Widget _assignWorkflowCard() {
    final canInteract = !_assigningWorkflow && !_saving && !_downloading && !_changingWorkflow;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Workflow', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (_assigningWorkflow)
                const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'No workflow is assigned to this object.',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<WorkflowOption>>(
            future: _workflowsFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 6),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }

              if (snap.hasError) {
                return Text(
                  'Failed to load workflows: ${snap.error}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                );
              }

              final workflows = snap.data ?? [];
              if (workflows.isEmpty) {
                return Text(
                  'No workflows available for this object type/class.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                );
              }

              _selectedWorkflowId ??= workflows.first.id;

              return Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedWorkflowId,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: 'Workflow',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        isDense: true,
                      ),
                      items: workflows
                          .map((w) => DropdownMenuItem<int>(
                                value: w.id,
                                child: Text(w.title, overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: !canInteract ? null : (v) => setState(() => _selectedWorkflowId = v),
                    ),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton(
                    onPressed: (!canInteract || _selectedWorkflowId == null)
                        ? null
                        : () async {
                            setState(() => _assigningWorkflow = true);

                            try {
                              final workflowId = _selectedWorkflowId!;
                              final initialStateId = _initialStateForWorkflow(workflowId);

                              final svc = context.read<MFilesService>();
                              final ok = await svc.setObjectWorkflowState(
                                objectTypeId: widget.obj.objectTypeId,
                                objectId: widget.obj.id,
                                workflowId: workflowId,
                                stateId: initialStateId,
                              );

                              if (!ok) throw Exception(svc.error ?? 'Unknown');

                              if (!mounted) return;
                              setState(() {
                                _workflowFuture = _loadWorkflow();
                                _future = _loadProps();
                              });
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(e.toString()),
                                  backgroundColor: Colors.red.shade600,
                                ),
                              );
                            } finally {
                              if (mounted) setState(() => _assigningWorkflow = false);
                            }
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF072F5F),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 0,
                    ),
                    child: const Text('Assign'),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
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

      final ok = await svc.updateObjectProps(
        objectId: widget.obj.id,
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
        _filesFuture = _loadFiles();
        _workflowFuture = _loadWorkflow();
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmAndDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete object?'),
        content: const Text('This will move the object to Deleted items.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );

    if (ok != true) return;
    if (!mounted) return;

    final svc = context.read<MFilesService>();
    final success = await svc.deleteObject(
      objectId: widget.obj.id,
      classId: widget.obj.classId,
    );

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Deleted'), backgroundColor: Colors.green.shade600),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Delete failed: ${svc.error ?? 'Unknown'}'), backgroundColor: Colors.red.shade600),
      );
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
          // Edit / Close
          IconButton(
            onPressed: (_saving || _downloading || _changingWorkflow)
                ? null
                : () {
                    setState(() {
                      _editMode = !_editMode;
                      if (!_editMode) _dirty.clear();
                    });
                  },
            icon: Icon(_editMode ? Icons.close : Icons.edit),
          ),

          // ✅ Only show Tick when editing
          if (_editMode)
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

          // Delete
          IconButton(
            onPressed: (_saving || _downloading || _changingWorkflow) ? null : _confirmAndDelete,
            icon: const Icon(Icons.delete_outline),
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
                _filesFuture = _loadFiles();
                _workflowFuture = _loadWorkflow();
                _commentsFuture = _loadComments();
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
                FutureBuilder<WorkflowInfo?>(
                  future: _workflowFuture,
                  builder: (context, wsnap) {
                    if (wsnap.connectionState == ConnectionState.waiting) return const SizedBox.shrink();
                    final info = wsnap.data;

                    return Column(
                      children: [
                        const SizedBox(height: 12),
                        if (info == null) _assignWorkflowCard() else _workflowCard(info),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 12),
                _previewCard(obj),
                const SizedBox(height: 12),
                //_permissionsCard(obj),
                _commentsCard(),
                const SizedBox(height: 12),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- everything below unchanged (your existing methods) ---
  // _headerCard, _metadataCard, _propField, _previewCard, _permissionsCard, _kv, _PropVm ...

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
            crossFadeState: _headerDetailsExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
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
      final hasValue = _lookupDisplayText(p).trim().isNotEmpty;

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
                    title: '',
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
                  hasValue ? 'Selected' : 'Select',
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

  Future<void> _openFileFromPreview(ViewObject obj, ObjectFile f) async {
    final displayIdInt = int.tryParse(obj.displayId);
    if (displayIdInt == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Invalid object display ID: ${obj.displayId}'),
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
        classId: obj.classId,
        fileId: f.fileId,
        fileTitle: f.fileTitle,
        extension: f.extension,
        reportGuid: f.reportGuid,
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


  Widget _previewCard(ViewObject obj) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Preview', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (_downloading)
                const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 10),
          FutureBuilder<List<ObjectFile>>(
            future: _filesFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 10),
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              if (snap.hasError) {
                return Text(
                  'Failed to load files: ${snap.error}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                );
              }

              final files = snap.data ?? [];

              if (files.isEmpty) {
                return Column(
                  children: [
                    Icon(Icons.insert_drive_file_outlined, color: Colors.grey.shade400),
                    const SizedBox(height: 4),
                    Text(
                      'There are no files attached to this item yet.',
                      style: TextStyle(color: Colors.grey.shade600),
                      textAlign: TextAlign.center,
                    ),
                  ],
                );
              }

              return Column(
                children: files.map((f) {
                  final ext = (f.extension.isEmpty ? '' : '.${f.extension}').toLowerCase();

                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: ListTile(
                      dense: true,
                      leading: const Icon(Icons.insert_drive_file_outlined),
                      title: Text(
                        f.fileTitle.isEmpty ? 'File ${f.fileId}' : f.fileTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text('v${f.fileVersion}${ext.isEmpty ? '' : ' • $ext'}'),

                      // tap anywhere on the row opens the document
                      onTap: (_saving || _downloading || _changingWorkflow) ? null : () => _openFileFromPreview(obj, f),

                      trailing: PopupMenuButton<String>(
                        onSelected: (action) async {
                          // IMPORTANT: your download endpoints require displayObjectId as int.
                          final displayIdInt = int.tryParse(obj.displayId);
                          if (displayIdInt == null) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Invalid object display ID: ${obj.displayId}'),
                                backgroundColor: Colors.red.shade600,
                              ),
                            );
                            return;
                          }

                          setState(() => _downloading = true);
                          try {
                            final svc = context.read<MFilesService>();

                            if (action == 'open') {
                              await svc.downloadAndOpenFile(
                                displayObjectId: displayIdInt,
                                classId: obj.classId,
                                fileId: f.fileId,
                                fileTitle: f.fileTitle,
                                extension: f.extension,
                                reportGuid: f.reportGuid,
                              );
                            }

                            if (action == 'download') {
                              final savedPath = await svc.downloadAndSaveFile(
                                displayObjectId: displayIdInt,
                                classId: obj.classId,
                                fileId: f.fileId,
                                fileTitle: f.fileTitle,
                                extension: f.extension,
                                reportGuid: f.reportGuid,
                              );

                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Saved to: $savedPath'),
                                  backgroundColor: Colors.green.shade600,
                                  duration: const Duration(seconds: 4),
                                ),
                              );
                            }
                          } catch (e) {
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Action failed: $e'),
                                backgroundColor: Colors.red.shade600,
                              ),
                            );
                          } finally {
                            if (mounted) setState(() => _downloading = false);
                          }
                        },
                        itemBuilder: (_) => const [
                          PopupMenuItem(value: 'open', child: Text('Open')),
                          PopupMenuItem(value: 'download', child: Text('Download')),
                        ],
                        child: const Icon(Icons.more_vert, size: 18),
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  /*... Widget _permissionsCard(ViewObject obj) {
    final p = obj.userPermission;

    if (p == null) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
        child: Text(
          'Permissions not available for this item.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
        ),
      );
    }

    Widget chip(String label, bool ok) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(ok ? Icons.check_circle : Icons.cancel,
              size: 16, color: ok ? Colors.green.shade700 : Colors.red.shade600),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Permissions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            runSpacing: 10,
            children: [
              chip('Read', p.readPermission),
              chip('Edit', p.editPermission),
              chip('Delete', p.deletePermission),
              chip('Attach', p.attachObjectsPermission),
            ],
          ),
          if (p.isClassDeleted)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                'Warning: class is deleted.',
                style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
              ),
            ),
        ],
      ),
    );
  } ...*/

  Future<List<ObjectComment>> _loadComments() async {
    final svc = context.read<MFilesService>();
    return svc.fetchComments(
      objectId: widget.obj.id,
      objectTypeId: widget.obj.objectTypeId,
      vaultGuid: svc.vaultGuidWithBraces,
    );
  }

  Future<void> _submitComment() async {
    final text = _commentCtrl.text.trim();
    if (text.isEmpty) return;
    if (_postingComment) return;

    setState(() => _postingComment = true);
    try {
      final svc = context.read<MFilesService>();
      final ok = await svc.postComment(
        comment: text,
        objectId: widget.obj.id,
        objectTypeId: widget.obj.objectTypeId,
        vaultGuid: svc.vaultGuidWithBraces,
      );

      if (!ok) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Comment failed: ${svc.error ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }

      _commentCtrl.clear();
      if (!mounted) return;
      setState(() {
        _commentsFuture = _loadComments();
      });
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  String _fmtCommentDate(DateTime? dt) {
  if (dt == null) return '';
  // Keep simple; you can switch to intl DateFormat if you want.
  return dt.toLocal().toString();
}

  Widget _commentsCard() {
    final disabled = _saving || _downloading || _changingWorkflow || _assigningWorkflow;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text('Comments', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (_postingComment)
                const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2)),
            ],
          ),
          const SizedBox(height: 10),

          // List
          FutureBuilder<List<ObjectComment>>(
            future: _commentsFuture,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: LinearProgressIndicator(minHeight: 2),
                );
              }
              if (snap.hasError) {
                return Text(
                  'Failed to load comments: ${snap.error}',
                  style: TextStyle(fontSize: 12, color: Colors.red.shade700),
                );
              }

              final items = snap.data ?? [];
              if (items.isEmpty) {
                return Text(
                  'No comments yet.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                );
              }

              return Column(
                children: items.map((c) {
                  final dateText = _fmtCommentDate(c.modifiedDate);
                  return Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(c.text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                        if (dateText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(dateText, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                        ],
                      ],
                    ),
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 10),

          // Composer
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _commentCtrl,
                  enabled: !disabled && !_postingComment,
                  minLines: 1,
                  maxLines: 3,
                  decoration: InputDecoration(
                    hintText: 'Write a comment…',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton(
                onPressed: (disabled || _postingComment) ? null : _submitComment,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF072F5F),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Post'),
              ),
            ],
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
          SizedBox(width: 110, child: Text(k, style: TextStyle(fontSize: 12, color: Colors.grey.shade700))),
          Expanded(
            child: Text(v.isEmpty ? '-' : v, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }
}

class _PropVm {
  final int id;
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
