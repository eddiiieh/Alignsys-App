// object_details_screen.dart
// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
import 'package:provider/provider.dart';
import 'package:mfiles_app/screens/document_preview_screen.dart';

import '../services/mfiles_service.dart';
import '../models/view_object.dart';
import '../models/object_file.dart';
import '../models/object_comment.dart';
import '../widgets/lookup_field.dart';
import 'package:mfiles_app/widgets/breadcrumb_bar.dart';
import 'package:mfiles_app/widgets/network_banner.dart';
import '../theme/app_colors.dart';
import 'package:mfiles_app/dss/screens/dss_signing_screen.dart';
import 'package:mfiles_app/utils/object_type_icons.dart';

class ObjectDetailsScreen extends StatefulWidget {
  final ViewObject obj;
  final String? parentViewName;
  final String? parentSection;
  final String? groupingName;

  const ObjectDetailsScreen({
    super.key,
    required this.obj,
    this.parentViewName,
    this.parentSection,
    this.groupingName,
  });

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

  // _editingPropId == null  →  no field is being edited
  // _editingPropId == p.id  →  that field's inline editor is open
  int? _editingPropId;

  bool _saving = false;
  bool _downloading = false;

  // e-Sign state
  bool _eSigning = false;

  // Assignment completion (legacy simple button fallback)
  bool _completingAssignment = false;
  bool _assignmentCompleted = false;

  // ── Per-user approval state ──
  final Set<int> _approvedUserIds = {};
  final Set<int> _approvingUserIds = {};

  bool _headerDetailsExpanded = false;

  String _title = '';

  final Map<int, String> _propNameById = {};
  final Set<int> _allowedMetaPropIds = {};
  static const Set<int> _excludeMetaPropIds = {100}; // Class
  final Map<int, _PropVm> _dirty = {};

  final Map<int, List<String>> _dirtyLookupLabels = {};

  // ── Per-field TextEditingControllers so we can show an inline editor ──
  final Map<int, TextEditingController> _fieldCtrl = {};

  final ScrollController _pageScroll = ScrollController();

  // Comments
  late Future<List<ObjectComment>> _commentsFuture;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _postingComment = false;
  final FocusNode _commentFocusNode = FocusNode();
  bool _commentInputFocused = false;
  bool _commentsExpanded = true;

  // ── Design constants ──
  static const _filledBorder = Color(0xFF2563EB);
  static const _filledFill = Color(0xFFF0F6FF);

  // ── Design constant — fields visible before "Show all" ──
  static const int _metaPreviewCount = 5;

  // ── Collapsible metadata state ──
  bool _metadataExpanded = false;

  String _currentUserInitials = '';

  final GlobalKey _commentInputKey = GlobalKey();

  bool get _isAssignment =>
      widget.obj.classId == -100 ||
      widget.obj.classTypeName.trim().toLowerCase() == 'assignment';

  @override
void initState() {
  super.initState();
  _title = widget.obj.title;

  // Initialise with empty futures so FutureBuilders don't crash before
  // the first frame — then load everything safely after the frame is done.
  _commentsFuture = Future.value([]);
  _future = Future.value([]);
  _filesFuture = Future.value([]);
  _workflowFuture = Future.value(null);
  _workflowsFuture = Future.value([]);

  _commentFocusNode.addListener(() {
    if (mounted) {
      setState(() => _commentInputFocused = _commentFocusNode.hasFocus);
      if (_commentFocusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 350), () {
          if (!mounted) return;
          final ctx = _commentInputKey.currentContext;
          if (ctx != null) {
            Scrollable.ensureVisible(
              ctx,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
            );
          }
        });
      }
    }
  });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final svc = context.read<MFilesService>();
      final name = svc.userEmail ?? svc.username ?? '';
      final parts = name.split(RegExp(r'[@\s.]')).where((s) => s.isNotEmpty).toList();
      setState(() {
        _currentUserInitials = parts.length >= 2
            ? '${parts.first[0]}${parts[1][0]}'.toUpperCase()
            : name.substring(0, name.length.clamp(0, 2)).toUpperCase();

        // Now safe to start loading — frame is fully built
        _commentsFuture = _loadComments();
        _future = _loadProps();
        _filesFuture = _loadFiles();
        _workflowFuture = _loadWorkflow();
        _workflowsFuture = _loadWorkflowsForThisObject();
      });
      svc.syncCheckoutStateFromServer(widget.obj.id, widget.obj.isCheckedOut);
    });
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    _commentCtrl.dispose();
    _commentFocusNode.dispose();
    for (final c in _fieldCtrl.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Open a single field for editing ──────────────────────────────────────
  void _startEditingField(_PropVm p, String currentText) {
    _cancelEditingField();
    final ctrl = TextEditingController(text: currentText);
    _fieldCtrl[p.id] = ctrl;
    setState(() => _editingPropId = p.id);
  }

  // ── Cancel / close without saving ────────────────────────────────────────
  void _cancelEditingField() {
    if (_editingPropId == null) return;
    final old = _editingPropId!;
    _fieldCtrl[old]?.dispose();
    _fieldCtrl.remove(old);
    setState(() {
      _editingPropId = null;
      _dirty.remove(old);
      _dirtyLookupLabels.remove(old);
    });
  }

  // ── Save a single field ───────────────────────────────────────────────────
  Future<void> _saveField(_PropVm p) async {
    if (!_dirty.containsKey(p.id)) {
      _cancelEditingField();
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final svc = context.read<MFilesService>();
      final dirty = _dirty[p.id]!;
      dynamic v = dirty.editedValue ?? dirty.value ?? '';

      if (p.datatype == 'MFDatatypeLookup') {
        if (v is int) v = v.toString();
        if (v is List<int> && v.isNotEmpty) v = v.first.toString();
      } else if (p.datatype == 'MFDatatypeMultiSelectLookup') {
        if (v is List<int>) v = v.map((x) => x.toString()).join(',');
      }

      final ok = await svc.updateObjectProps(
        objectId: widget.obj.id,
        objectTypeId: widget.obj.objectTypeId,
        classId: widget.obj.classId,
        props: [
          {"id": p.id, "value": v.toString(), "datatype": p.datatype}
        ],
      );

      if (!mounted) return;

      if (!ok) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Update failed: ${svc.error ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }

      _dirty.remove(p.id);
      _dirtyLookupLabels.remove(p.id);
      _fieldCtrl[p.id]?.dispose();
      _fieldCtrl.remove(p.id);

      setState(() {
        _editingPropId = null;
        _future = _loadProps();
        _filesFuture = _loadFiles();
        _workflowFuture = _loadWorkflow();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 16),
            SizedBox(width: 8),
            Text('Saved'),
          ]),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
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
  bool _isDate(_PropVm p) => p.datatype == 'MFDatatypeDate';
  bool _isTimestamp(_PropVm p) => p.datatype == 'MFDatatypeTimestamp';
  bool _isBoolean(_PropVm p) => p.datatype == 'MFDatatypeBoolean';


  List<int> _selectedIdsForLookup(_PropVm p, {required bool isMulti}) {
    final source = _dirty[p.id]?.editedValue ?? p.value;

    int? toInt(dynamic x) {
      if (x == null) return null;
      if (x is int) return x;
      if (x is num) return x.toInt();
      if (x is String) return int.tryParse(x.trim());
      if (x is Map) {
        final id = x['id'] ?? x['itemId'] ?? x['value'];
        if (id is int) return id;
        if (id is num) return id.toInt();
        if (id is String) return int.tryParse(id.trim());
      }
      return null;
    }

    if (isMulti) {
      if (source is List<int>) return List<int>.from(source);
      if (source is List) return source.map(toInt).whereType<int>().toList();
      if (source is String && source.contains(',')) {
        return source
            .split(',')
            .map((s) => int.tryParse(s.trim()))
            .whereType<int>()
            .toList();
      }
      final one = toInt(source);
      return one == null ? <int>[] : <int>[one];
    }

    final one = toInt(source);
    return one == null ? <int>[] : <int>[one];
  }

  List<String> _selectedLabelsForLookup(_PropVm p) {
    if (_dirtyLookupLabels.containsKey(p.id)) {
      return _dirtyLookupLabels[p.id]!;
    }

    final source = _dirty[p.id]?.editedValue ?? p.value;

    if (source is int || source is List<int>) return const <String>[];

    final out = <String>[];

    void addFrom(dynamic x) {
      if (x == null) return;
      if (x is String) {
        final t = x.trim();
        if (t.isNotEmpty) out.add(t);
        return;
      }
      if (x is Map) {
        final t = (x['displayValue'] ?? x['title'] ?? x['name'])?.toString();
        if (t != null && t.trim().isNotEmpty) out.add(t.trim());
        return;
      }
      final s = x.toString().trim();
      if (s.isNotEmpty) out.add(s);
    }

    if (source is List) {
      for (final e in source) addFrom(e);
    } else {
      addFrom(source);
    }

    return out.toSet().toList();
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
    if (candidate.trim().isNotEmpty) _scheduleTitleUpdate(candidate);
  }

  Widget _buildBreadcrumbs() {
    final segments = <BreadcrumbSegment>[
      BreadcrumbSegment(
        label: 'Home',
        icon: Icons.home_rounded,
        onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      ),
    ];
    if (widget.parentViewName != null) {
      segments.add(BreadcrumbSegment(
        label: widget.parentViewName!,
        onTap: () {
          if (widget.groupingName != null) {
            Navigator.pop(context);
            Navigator.pop(context);
          } else {
            Navigator.pop(context);
          }
        },
      ));
    }
    if (widget.groupingName != null) {
      segments.add(BreadcrumbSegment(
        label: widget.groupingName!,
        onTap: () => Navigator.pop(context),
      ));
    }
    final objTitle = _title.isEmpty ? widget.obj.title : _title;
    final displayTitle = objTitle.length > 30 ? '${objTitle.substring(0, 30)}...' : objTitle;
    segments.add(BreadcrumbSegment(label: displayTitle));
    return BreadcrumbBar(segments: segments);
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

      // ── ADD THIS: if class properties returned very few results,
      //    fall back to showing all raw props instead of filtering
      if (svc.classProperties.length <= 2) {
        _allowedMetaPropIds.clear();
        // will be populated from raw props below
      }

    _propNameById
      ..clear()
      ..addAll({0: 'Name or title', 100: 'Class'})
      ..addEntries(svc.classProperties.map((p) => MapEntry(p.id, p.title)));

    final displayIdInt = int.tryParse(widget.obj.displayId) ?? widget.obj.id;
    debugPrint(
      'fetchObjectViewProps → '
      'id=${widget.obj.id} '
      'displayId=${widget.obj.displayId} '
      'classId=${widget.obj.classId} '
      'objectTypeId=${widget.obj.objectTypeId} '
      'title=${widget.obj.title}',
    );
    final raw = await svc.fetchObjectViewProps(
      objectId: displayIdInt,
      objectTypeId: widget.obj.objectTypeId,
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

    // ── ADD THIS ──
    if (_allowedMetaPropIds.isEmpty) {
      _allowedMetaPropIds.addAll(
        vms.map((p) => p.id).where((id) => !_excludeMetaPropIds.contains(id)),
      );
    }

    _maybeUpdateTitleFromProps(vms);

    debugPrint('classProperties count: ${svc.classProperties.length}');
    debugPrint('allowedMetaPropIds: $_allowedMetaPropIds');
    debugPrint('raw props count: ${raw.length}');
    debugPrint('raw prop IDs: ${raw.map((m) => m['id'] ?? m['propId']).toList()}');

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

  // ── Show a dialog with the object's automatic permissions ──────────────────
  void _showAutoPermissionsDialog() {
    final obj = widget.obj;
    final perms = obj.userPermission;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F6FF),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline_rounded,
                      size: 18, color: AppColors.primary),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Automatic Permissions',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(ctx),
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(Icons.close,
                          size: 16, color: Colors.grey.shade600),
                    ),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Object Information ───────────────────────────────
                  const Text(
                    'Object Information',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _permKv('Title', _title.isEmpty ? obj.title : _title),
                        const SizedBox(height: 6),
                        _permKv('Type', obj.objectTypeName),
                        const SizedBox(height: 6),
                        _permKv('Class', obj.classTypeName),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // ── User Permissions ─────────────────────────────────
                  const Text(
                    'User Permissions',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Table(
                      border: TableBorder(
                        horizontalInside: BorderSide(
                            color: Colors.grey.shade100, width: 1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      children: [
                        // Header row
                        TableRow(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: const BorderRadius.vertical(
                                top: Radius.circular(10)),
                          ),
                          children: [
                            _permTableHeader('Read'),
                            _permTableHeader('Edit'),
                            _permTableHeader('Delete'),
                            _permTableHeader('Attach')
                          ],
                        ),
                        // Values row
                        TableRow(
                          children: [
                            _permTableCell(perms?.readPermission ?? false),
                            _permTableCell(perms?.editPermission ?? false),
                            _permTableCell(perms?.deletePermission ?? false),
                            _permTableCell(perms?.attachObjectsPermission ?? false),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _permKv(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  Widget _permTableHeader(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Color(0xFF475569),
          ),
        ),
      ),
    );
  }

  Widget _permTableCell(bool allowed) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Icon(
          allowed ? Icons.check_rounded : Icons.close_rounded,
          size: 20,
          color: allowed ? const Color(0xFF22C55E) : const Color(0xFFEF4444),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // e-SIGN ─ SEND FOR SIGNING DIALOG
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _showSendForSigningDialog(ObjectFile file) async {
    await showDialog(
      context: context,
      builder: (_) => _SendForSigningDialog(
        file: file,
        onSend: (emails) => _sendForSigning(file: file, emails: emails),
      ),
    );
  }

  Future<void> _sendForSigning({
    required ObjectFile file,
    required List<String> emails,
  }) async {
    final svc = context.read<MFilesService>();
    final displayIdInt = int.tryParse(widget.obj.displayId) ?? widget.obj.id;
    try {
      for (final email in emails) {
        await svc.dssPostObjectFile(
          objectId: displayIdInt,
          classId: widget.obj.classId,
          fileId: file.fileId,
          versionId: file.fileVersion,
          vaultGuid: svc.vaultGuidWithBraces,
          signerEmail: email,
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Text(
                'Sent for signing to ${emails.length} signee${emails.length == 1 ? '' : 's'}'),
          ]),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to send: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  Future<void> _selfSign(ObjectFile file) async {
    final svc = context.read<MFilesService>();
    final displayIdInt = int.tryParse(widget.obj.displayId) ?? widget.obj.id;
    final userEmail = svc.userEmail ?? svc.username ?? '';

    setState(() => _eSigning = true);
    try {
      final signingUrl = await svc.dssSelfSign(
        objectId: displayIdInt,
        classId: widget.obj.classId,
        fileId: file.fileId,
        versionId: file.fileVersion,
        vaultGuid: svc.vaultGuidWithBraces,
        signerEmail: userEmail,
        userId: svc.mfilesUserId ?? 0,
      );

      if (!mounted) return;
      setState(() => _eSigning = false);

      final signed = await Navigator.push<bool>(
        context,
        MaterialPageRoute(
          builder: (_) => DssSigningScreen(signingUrl: signingUrl),
        ),
      );

      if (signed == true && mounted) {
        setState(() {
          _future = _loadProps();
          _filesFuture = _loadFiles();
          _workflowFuture = _loadWorkflow();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Document signing completed'),
            ]),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _eSigning = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Signing failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10)),
        ),
      );
    }
  }

  //e-Sign options bottom sheet, DO NOT REMOVE
  void _showESignOptions(ObjectFile file) {
    final busy = _saving || _downloading || _changingWorkflow || _eSigning;
    if (busy) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 28),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 18),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.draw_rounded, color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('e-Sign options',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    SizedBox(height: 2),
                    Text('Choose a signing action',
                        style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                  ],
                ),
              ]),
              const SizedBox(height: 20),
              // Sign myself
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(context);
                    _selfSign(file);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: AppColors.primary.withOpacity(0.15)),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.draw_outlined, size: 18, color: AppColors.primary),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Sign myself',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          SizedBox(height: 2),
                          Text('Sign this document with your own signature',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                    ]),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // Send for signing
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(context);
                    _showSendForSigningDialog(file);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.send_rounded, size: 18, color: Colors.grey.shade600),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          const Text('Send for signing',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text('Request signatures from others via email',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                        ]),
                      ),
                      Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
                    ]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WORKFLOW CARD HELPERS
  // ─────────────────────────────────────────────────────────────────────────
  Widget _descriptionBox({required String desc, required bool isAssignedToMe}) {
    if (isAssignedToMe) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFFFCC02).withOpacity(0.25),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.7)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.person_pin_outlined,
                    size: 11, color: Color(0xFF92700A)),
                const SizedBox(width: 4),
                const Text(
                  'Assigned to you',
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF92700A),
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border:
                  Border.all(color: const Color(0xFFFFCC02).withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.assignment_ind_outlined,
                    size: 15, color: Color(0xFF92700A)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    desc,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF5C4A00),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withOpacity(0.12)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 15, color: Colors.grey.shade600),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              desc,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF334155),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ASSIGNMENT APPROVAL HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  List<int> _assignedUserIds(List<_PropVm> props) {
    final candidates = props.where((p) {
      final n = (_propNameById[p.id] ?? p.name).toLowerCase();
      return n.contains('assign') &&
          (p.datatype == 'MFDatatypeMultiSelectLookup' ||
              p.datatype == 'MFDatatypeLookup');
    }).toList();

    int? toInt(dynamic x) {
      if (x is int) return x;
      if (x is num) return x.toInt();
      if (x is String) return int.tryParse(x.trim());
      if (x is Map) {
        final id = x['id'] ?? x['itemId'] ?? x['value'];
        if (id is int) return id;
        if (id is num) return id.toInt();
        if (id is String) return int.tryParse(id.trim());
      }
      return null;
    }

    final ids = <int>{};
    for (final p in candidates) {
      final source = p.value;
      if (source is List) {
        ids.addAll(source.map(toInt).whereType<int>());
      } else {
        final id = toInt(source);
        if (id != null) ids.add(id);
      }
    }
    return ids.toList();
  }

  Map<int, String> _assignedUserLabels(List<_PropVm> props) {
    final out = <int, String>{};
    final candidates = props.where((p) {
      final n = (_propNameById[p.id] ?? p.name).toLowerCase();
      return n.contains('assign') &&
          (p.datatype == 'MFDatatypeMultiSelectLookup' ||
              p.datatype == 'MFDatatypeLookup');
    }).toList();

    void addFromMap(dynamic x) {
      if (x is! Map) return;
      final rawId = x['id'] ?? x['itemId'] ?? x['value'];
      int? id;
      if (rawId is int) id = rawId;
      if (rawId is num) id = rawId.toInt();
      if (rawId is String) id = int.tryParse(rawId.trim());
      if (id == null) return;
      final label =
          (x['displayValue'] ?? x['title'] ?? x['name'])?.toString().trim() ??
              '';
      if (label.isNotEmpty) out[id] = label;
    }

    for (final p in candidates) {
      final source = p.value;
      if (source is List) {
        for (final e in source) addFromMap(e);
      } else {
        addFromMap(source);
      }
    }
    return out;
  }

  Future<void> _toggleApproval({
    required int userId,
    required bool currentlyApproved,
  }) async {
    if (_approvingUserIds.contains(userId)) return;

    setState(() => _approvingUserIds.add(userId));
    try {
      final svc = context.read<MFilesService>();
      final ok = await svc.approveAssignment(
        objectId: widget.obj.id,
        classId: widget.obj.classId,
        userId: userId,
        approve: !currentlyApproved,
      );

      if (!mounted) return;

      if (ok) {
        setState(() {
          if (!currentlyApproved) {
            _approvedUserIds.add(userId);
          } else {
            _approvedUserIds.remove(userId);
          }
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              Icon(
                !currentlyApproved ? Icons.check_circle : Icons.undo,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(!currentlyApproved
                  ? 'Assignment approved'
                  : 'Approval withdrawn'),
            ]),
            backgroundColor: !currentlyApproved
                ? Colors.green.shade600
                : Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        setState(() {
          _future = _loadProps();
          _workflowFuture = _loadWorkflow();
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${svc.error ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _approvingUserIds.remove(userId));
    }
  }

  Widget _buildAssignmentApprovalSection(List<_PropVm> props) {
    final svc = context.read<MFilesService>();
    final int? currentUserId = svc.mfilesUserId;

    final assignedIds = _assignedUserIds(props);
    final labels = _assignedUserLabels(props);

    if (assignedIds.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: (_assignmentCompleted ||
                  _completingAssignment ||
                  _saving ||
                  _downloading)
              ? null
              : _markAssignmentComplete,
          style: ElevatedButton.styleFrom(
            backgroundColor:
                _assignmentCompleted ? const Color(0xFFE8F5E9) : AppColors.primary,
            foregroundColor: _assignmentCompleted
                ? const Color(0xFF2E7D32)
                : Colors.white,
            disabledBackgroundColor: _assignmentCompleted
                ? const Color(0xFFE8F5E9)
                : Colors.grey.shade200,
            disabledForegroundColor: _assignmentCompleted
                ? const Color(0xFF2E7D32)
                : Colors.grey.shade400,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _completingAssignment
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : Icon(
                  _assignmentCompleted
                      ? Icons.check_circle
                      : Icons.check_circle_outline,
                  size: 18,
                ),
          label: Text(
            _completingAssignment
                ? 'Completing...'
                : _assignmentCompleted
                    ? 'Marked as Complete'
                    : 'Mark as Complete',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'APPROVALS',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFF475569),
            letterSpacing: 1.0,
          ),
        ),
        const SizedBox(height: 10),
        ...assignedIds.map((uid) {
          final isMe = uid == currentUserId;
          final isApproved = _approvedUserIds.contains(uid);
          final isBusy = _approvingUserIds.contains(uid);
          final isBusyGlobal = _saving || _downloading || _completingAssignment;

          final rawLabel = labels[uid] ?? 'User $uid';
          final nameParts =
              rawLabel.split(' ').where((s) => s.isNotEmpty).toList();
          final initials = nameParts.length >= 2
              ? '${nameParts.first[0]}${nameParts.last[0]}'.toUpperCase()
              : rawLabel
                  .substring(0, rawLabel.length.clamp(0, 2))
                  .toUpperCase();

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isApproved
                  ? const Color(0xFFE8F5E9)
                  : isMe
                      ? const Color(0xFFF0F6FF)
                      : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isApproved
                    ? const Color(0xFF4CAF50).withOpacity(0.4)
                    : isMe
                        ? const Color(0xFF2563EB).withOpacity(0.3)
                        : Colors.grey.shade200,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isMe ? AppColors.primary : Colors.grey.shade300,
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: isMe ? Colors.white : Colors.grey.shade600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              rawLabel,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: isMe
                                    ? AppColors.primary
                                    : const Color(0xFF334155),
                              ),
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.primary.withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'You',
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
                      const SizedBox(height: 2),
                      Text(
                        isApproved ? 'Approved ✓' : 'Pending approval',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                          color: isApproved
                              ? Colors.green.shade600
                              : AppColors.surfaceLight,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (isBusy)
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!isMe)
                  Icon(
                    isApproved
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    size: 24,
                    color: isApproved
                        ? Colors.green.shade500
                        : Colors.grey.shade300,
                  )
                else
                  Tooltip(
                    message:
                        isApproved ? 'Withdraw approval' : 'Approve assignment',
                    child: GestureDetector(
                      onTap: isBusyGlobal
                          ? null
                          : () => _toggleApproval(
                                userId: uid,
                                currentlyApproved: isApproved,
                              ),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: isApproved
                              ? Colors.green.shade500
                              : Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isBusyGlobal
                                ? Colors.grey.shade300
                                : isApproved
                                    ? Colors.green.shade500
                                    : const Color(0xFF2563EB),
                            width: 2,
                          ),
                          boxShadow: isMe && !isApproved
                              ? [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.15),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2),
                                  )
                                ]
                              : null,
                        ),
                        child: isApproved
                            ? const Icon(Icons.check,
                                size: 16, color: Colors.white)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          );
        }),
      ],
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
    final canInteract =
        !_assigningWorkflow && !_saving && !_downloading && !_changingWorkflow;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Workflow',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (_assigningWorkflow)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── No workflow notice ─────────────────────────────────────
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 15, color: Colors.grey.shade400),
                      const SizedBox(width: 8),
                      Text(
                        'No workflow assigned to this object',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Divider(height: 1, color: Colors.grey.shade100),
                const SizedBox(height: 14),

                // ── Assign section ─────────────────────────────────────────
                Row(
                  children: [
                    const Icon(Icons.add_circle_outline_rounded,
                        size: 14, color: AppColors.primary),
                    const SizedBox(width: 6),
                    const Text(
                      'ASSIGN WORKFLOW',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                FutureBuilder<List<WorkflowOption>>(
                  future: _workflowsFuture,
                  builder: (context, snap) {
                    if (snap.connectionState == ConnectionState.waiting) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      );
                    }
                    if (snap.hasError) {
                      return Text(
                        'Failed to load workflows: ${snap.error}',
                        style: TextStyle(
                            fontSize: 12, color: Colors.red.shade700),
                      );
                    }
                    final workflows = snap.data ?? [];
                    if (workflows.isEmpty) {
                      return Text(
                        'No workflows available for this object type.',
                        style: TextStyle(
                            fontSize: 13, color: Colors.grey.shade500),
                      );
                    }
                    _selectedWorkflowId ??= workflows.first.id;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(10),
                              border:
                                  Border.all(color: Colors.grey.shade200),
                            ),
                            child: DropdownButtonHideUnderline(
                              child: ButtonTheme(
                                alignedDropdown: true,
                                child: DropdownButton<int>(
                                  value: _selectedWorkflowId,
                                  isExpanded: true,
                                  isDense: true,
                                  style: const TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF1E293B),
                                  ),
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    color: Colors.grey.shade500,
                                    size: 20,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 10),
                                  borderRadius: BorderRadius.circular(10),
                                  items: workflows
                                      .map((w) => DropdownMenuItem<int>(
                                            value: w.id,
                                            child: Text(
                                              w.title,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                fontSize: 13.5,
                                                fontWeight: FontWeight.w500,
                                                color: Color(0xFF1E293B),
                                              ),
                                            ),
                                          ))
                                      .toList(),
                                  onChanged: !canInteract
                                      ? null
                                      : (v) => setState(
                                          () => _selectedWorkflowId = v),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          height: 44,
                          child: ElevatedButton(
                            onPressed: (!canInteract ||
                                    _selectedWorkflowId == null)
                                ? null
                                : () async {
                                    setState(
                                        () => _assigningWorkflow = true);
                                    try {
                                      final workflowId = _selectedWorkflowId!;
                                      final initialStateId =
                                          _initialStateForWorkflow(workflowId);
                                      final svc =
                                          context.read<MFilesService>();
                                      final ok =
                                          await svc.setObjectWorkflowState(
                                        objectTypeId: widget.obj.objectTypeId,
                                        objectId: widget.obj.id,
                                        workflowId: workflowId,
                                        stateId: initialStateId,
                                      );
                                      if (!ok) {
                                        throw Exception(
                                            svc.error ?? 'Unknown');
                                      }
                                      if (!mounted) return;
                                      setState(() {
                                        _workflowFuture = _loadWorkflow();
                                        _future = _loadProps();
                                      });
                                    } catch (e) {
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        SnackBar(
                                          content: Text(e.toString()),
                                          backgroundColor: Colors.red.shade600,
                                        ),
                                      );
                                    } finally {
                                      if (mounted) {
                                        setState(
                                            () => _assigningWorkflow = false);
                                      }
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              disabledBackgroundColor: Colors.grey.shade200,
                              disabledForegroundColor: Colors.grey.shade400,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20),
                            ),
                            child: const Text(
                              'Assign',
                              style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmAndDelete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete object?'),
        content: const Text('This will move the object to Deleted items.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Delete')),
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
        SnackBar(
            content: const Text('Deleted'),
            backgroundColor: Colors.green.shade600),
      );
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Delete failed: ${svc.error ?? 'Unknown'}'),
          backgroundColor: Colors.red.shade600,
        ),
      );
    }
  }

  Future<void> _markAssignmentComplete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text(
          'Complete assignment?',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
        content: Text(
          'Mark this assignment as complete?\nThis cannot be undone.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Complete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _completingAssignment = true);
    try {
      final svc = context.read<MFilesService>();
      final ok = await svc.markAssignmentComplete(
        objectId: widget.obj.id,
        classId: widget.obj.classId,
      );
      if (!mounted) return;
      if (ok) {
        setState(() => _assignmentCompleted = true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(children: [
              Icon(Icons.check_circle, color: Colors.white, size: 18),
              SizedBox(width: 8),
              Text('Assignment marked as complete'),
            ]),
            backgroundColor: Colors.green.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed: ${svc.error ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _completingAssignment = false);
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  /// Parses a stored date/timestamp string back to a DateTime for pre-filling
  /// the picker. Accepts ISO 8601 and yyyy-MM-dd.
  DateTime? _parseDateValue(dynamic raw) {
    if (raw == null) return null;
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    try {
      return DateTime.parse(s);
    } catch (_) {
      return null;
    }
  }

  /// Formats a DateTime as the ISO 8601 string M-Files expects.
  /// Date-only:  yyyy-MM-dd
  /// Timestamp:  yyyy-MM-ddTHH:mm:ss
  String _formatForMFiles(DateTime dt, {required bool includeTime}) {
    final y = dt.year.toString().padLeft(4, '0');
    final mo = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    if (!includeTime) return '$y-$mo-$d';
    final h = dt.hour.toString().padLeft(2, '0');
    final mi = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y-$mo-${d}T$h:$mi:$s';
  }

  /// Human-readable display string shown in the read-only tile.
  String _displayDate(String isoValue, {required bool includeTime}) {
    final dt = _parseDateValue(isoValue);
    if (dt == null) return isoValue;
    final local = dt.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final mo = local.month.toString().padLeft(2, '0');
    final d = local.day.toString().padLeft(2, '0');
    if (!includeTime) return '$d/$mo/$y';
    final h = local.hour.toString().padLeft(2, '0');
    final mi = local.minute.toString().padLeft(2, '0');
    return '$d/$mo/$y $h:$mi';
  }

  /// Opens the date picker (and optionally time picker), marks the field dirty,
  /// then auto-saves so the user does not need to tap Save manually.
  Future<void> _pickDate(_PropVm p, {required bool includeTime}) async {
    final rawCurrent = _dirty[p.id]?.editedValue ?? p.value;
    final initial = _parseDateValue(rawCurrent) ?? DateTime.now();

    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: AppColors.primary),
        ),
        child: child!,
      ),
    );

    if (pickedDate == null || !mounted) return;

    DateTime finalDt = pickedDate;

    if (includeTime) {
      final pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: initial.hour, minute: initial.minute),
        builder: (ctx, child) => Theme(
          data: Theme.of(ctx).copyWith(
            colorScheme: const ColorScheme.light(primary: AppColors.primary),
          ),
          child: child!,
        ),
      );
      if (!mounted) return;
      if (pickedTime != null) {
        finalDt = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
      }
    }

    final iso = _formatForMFiles(finalDt, includeTime: includeTime);
    setState(() => _dirty[p.id] = p.copyWith(editedValue: iso));
    await _saveField(p);
  }

  @override
  Widget build(BuildContext context) {
    final obj = widget.obj;
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      // ── e-Sign FAB disabled: redundant now that the dedicated e-Sign card
      //    (_signingCard, rendered right after the preview card) covers the
      //    same actions. Uncomment to restore the floating shortcut.
      // floatingActionButton: FutureBuilder<List<ObjectFile>>(
      //   future: _filesFuture,
      //   builder: (context, snap) {
      //     final svc = context.watch<MFilesService>();
      //     final firstFile = (snap.data?.isNotEmpty ?? false) ? snap.data!.first : null;
      //     if (firstFile == null || !svc.isDssAvailable) return const SizedBox.shrink();
      //     return _ESignFab(
      //       onTap: () => _showESignOptions(firstFile),
      //       isBusy: _eSigning,
      //     );
      //   },
      // ),
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Text(
          _title.isEmpty ? obj.title : _title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, height: 1.2),
        ),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
          // ── TEMPORARY: smoke-test button for checkoutObject/undoCheckoutObject.
          //    Remove once the long-press multi-select menu ships this properly.
          Consumer<MFilesService>(
            builder: (context, svc, _) {
              final isCheckedOut = svc.isCheckedOutLocally(widget.obj.id);
              final busy = _saving || _downloading || _changingWorkflow;
              return IconButton(
                tooltip: isCheckedOut ? 'Check In' : 'Check Out',
                onPressed: busy
                    ? null
                    : () async {
                        final ok = isCheckedOut
                            ? await svc.undoCheckoutObject(
                                objectId: widget.obj.id,
                                objectTypeId: widget.obj.objectTypeId,
                              )
                            : await svc.checkoutObject(
                                objectId: widget.obj.id,
                                objectTypeId: widget.obj.objectTypeId,
                              );
                        final errorMsg = svc.error ?? 'Unknown error';
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                ok
                                    ? (isCheckedOut ? 'Checked in' : 'Checked out')
                                    : errorMsg == 'already_checked_out'
                                        ? 'Already checked out — status updated'
                                        : 'Failed: $errorMsg',
                              ),
                            backgroundColor: ok
                                ? Colors.green.shade600
                                : Colors.red.shade600,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                icon: Icon(
                  isCheckedOut ? Icons.file_open_rounded : Icons.drive_file_rename_outline,
                ),
              );
            },
          ),
          if (widget.obj.userPermission?.deletePermission ?? false)
            IconButton(
              onPressed:
                  (_saving || _downloading || _changingWorkflow)
                      ? null
                      : _confirmAndDelete,
              icon: const Icon(Icons.delete_outline),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: NetworkBanner(
        child: Column(
          children: [
            _buildBreadcrumbs(),
            Expanded(
              child: FutureBuilder<List<_PropVm>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (snap.hasError) {
                    return Center(child: Text('Error: ${snap.error}'));
                  }
                  final props = snap.data ?? [];
                  final metaProps = props
                      .where((p) => _allowedMetaPropIds.contains(p.id))
                      .toList();
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {
                        _future = _loadProps();
                        _filesFuture = _loadFiles();
                        _workflowFuture = _loadWorkflow();
                        _commentsFuture = _loadComments();
                        _dirty.clear();
                        _dirtyLookupLabels.clear();
                        _editingPropId = null;
                        _approvedUserIds.clear();
                        _approvingUserIds.clear();
                      });
                      await _future;
                    },
                    child: Scrollbar(
                      controller: _pageScroll,
                      thickness: 6,
                      radius: const Radius.circular(3),
                      interactive: true,
                      child: ListView(
                        controller: _pageScroll,
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                        children: [
                          // ── Header card ──────────────────────────────────
                          FutureBuilder<List<ObjectFile>>(
                            future: _filesFuture,
                            builder: (context, filesSnap) {
                              final firstFile =
                                  (filesSnap.data?.isNotEmpty ?? false)
                                      ? filesSnap.data!.first
                                      : null;
                              return _headerCard(obj, firstFile: firstFile);
                            },
                          ),
                          const SizedBox(height: 12),

                          // ── Metadata card ────────────────────────────────
                          _metadataCard(metaProps),

                          // ── Workflow card ────────────────────────────────
                          FutureBuilder<WorkflowInfo?>(
                            future: _workflowFuture,
                            builder: (context, wsnap) {
                              if (wsnap.connectionState ==
                                  ConnectionState.waiting) {
                                return const SizedBox.shrink();
                              }
                              final info = wsnap.data;
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  if (info == null)
                                    _assignWorkflowCard()
                                  else
                                    _buildWorkflowCardWithState(info),
                                ],
                              );
                            },
                          ),

                          // ── Preview card ─────────────────────────────────
                          FutureBuilder<List<ObjectFile>>(
                            future: _filesFuture,
                            builder: (context, previewSnap) {
                              final files = previewSnap.data;
                              if (files != null &&
                                  files.isEmpty &&
                                  widget.obj.objectTypeId != 0) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  _previewCard(obj),
                                ],
                              );
                            },
                          ),

                          // ── e-Signature card (separate, optional) ────────
                          FutureBuilder<List<ObjectFile>>(
                            future: _filesFuture,
                            builder: (context, sigSnap) {
                              final svc = context.read<MFilesService>();
                              final firstFile =
                                  (sigSnap.data?.isNotEmpty ?? false)
                                      ? sigSnap.data!.first
                                      : null;
                              if (firstFile == null) {
                                return const SizedBox.shrink();
                              }
                              return Column(
                                children: [
                                  const SizedBox(height: 12),
                                  _signingCard(firstFile),
                                ],
                              );
                            },
                          ),

                          // ── Comments card ────────────────────────────────
                          const SizedBox(height: 12),
                          _commentsCard(),
                          const SizedBox(height: 32),
                        ],
                      ),
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

  // ─────────────────────────────────────────────────────────────────────────
  // e-SIGNATURE CARD  ── standalone, clearly optional
  // ─────────────────────────────────────────────────────────────────────────

  Widget _signingCard(ObjectFile file) {
    final busy = _saving || _downloading || _changingWorkflow || _eSigning;
    final fileName = file.fileTitle.trim().isEmpty ? 'this file' : file.fileTitle;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ──────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.draw_rounded,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'e-Sign options',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (_eSigning)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          // ── Card body ────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Context note — makes it clear this is optional
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline,
                        size: 13, color: Colors.grey.shade400),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Optionally sign or send "$fileName" for signing.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                // ── Action buttons ───────────────────────────────────────
                Row(
                  children: [
                    // Sign Myself
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: busy ? null : () => _selfSign(file),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          elevation: 0,
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        icon: _eSigning
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : const Icon(Icons.draw_rounded, size: 15),
                        label: const Text('Sign Myself'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Send for Signing
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy
                            ? null
                            : () => _showSendForSigningDialog(file),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(vertical: 11),
                          elevation: 0,
                          textStyle: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w600),
                        ),
                        icon: const Icon(Icons.send_rounded, size: 15),
                        label: const Text('Send for Signing'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WORKFLOW CARD WITH STATE
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildWorkflowCardWithState(WorkflowInfo info) {
    final canChange = info.nextStates.isNotEmpty &&
        !_changingWorkflow &&
        !_saving &&
        !_downloading;
    final hasDesc = info.assignmentDesc.trim().isNotEmpty;
    final isAssignedToMe = info.isAssignedToMe;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Card header ─────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Workflow',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (_changingWorkflow)
                  const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Workflow name ──────────────────────────────────────────
                Text(
                  info.workflowTitle,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF0F172A),
                  ),
                ),
                const SizedBox(height: 12),

                // ── Current state pill ─────────────────────────────────────
                Row(
                  children: [
                    Text(
                      'Current state',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: Text(
                        info.currentStateTitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Assignment description ─────────────────────────────────
                if (hasDesc) ...[
                  const SizedBox(height: 14),
                  _descriptionBox(
                    desc: info.assignmentDesc.trim(),
                    isAssignedToMe: isAssignedToMe,
                  ),
                ],

                // ── Advance to ────────────────────────────────────────────
                if (info.nextStates.isEmpty) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.lock_outline_rounded,
                            size: 15, color: Colors.grey.shade400),
                        const SizedBox(width: 8),
                        Text(
                          'No further steps available',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 16),
                  Divider(height: 1, color: Colors.grey.shade100),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      const Icon(Icons.arrow_circle_right_outlined,
                          size: 14, color: AppColors.primary),
                      const SizedBox(width: 6),
                      const Text(
                        'ADVANCE TO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary,
                          letterSpacing: 0.8,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: DropdownButtonHideUnderline(
                            child: ButtonTheme(
                              alignedDropdown: true,
                              child: DropdownButton<int>(
                                value: _selectedNextStateId,
                                isExpanded: true,
                                isDense: true,
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF1E293B),
                                ),
                                icon: Icon(
                                  Icons.keyboard_arrow_down_rounded,
                                  color: Colors.grey.shade500,
                                  size: 20,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 10),
                                borderRadius: BorderRadius.circular(10),
                                items: info.nextStates
                                    .map((s) => DropdownMenuItem<int>(
                                          value: s.id,
                                          child: Text(
                                            s.title,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: FontWeight.w500,
                                              color: Color(0xFF1E293B),
                                            ),
                                          ),
                                        ))
                                    .toList(),
                                onChanged: canChange
                                    ? (v) => setState(
                                        () => _selectedNextStateId = v)
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      SizedBox(
                        height: 44,
                        child: ElevatedButton(
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
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                              'Workflow update failed: ${svc.error ?? 'Unknown'}'),
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
                                    if (mounted) {
                                      setState(() => _changingWorkflow = false);
                                    }
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            disabledBackgroundColor: Colors.grey.shade200,
                            disabledForegroundColor: Colors.grey.shade400,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(
                                fontSize: 13.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _headerCard(ViewObject obj, {ObjectFile? firstFile}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              firstFile != null
              ? _CheckoutBadge(
                  objectId: obj.id,
                  child: FileTypeBadge(extension: firstFile.extension, size: 36),
                )
              : _CheckoutBadge(
                  objectId: obj.id,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        iconForObjectTypeName(obj.objectTypeName),
                        size: 20,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _title.isEmpty ? obj.title : _title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    height: 1.3,
                  ),
                ),
              ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => setState(
                      () => _headerDetailsExpanded = !_headerDetailsExpanded),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      _headerDetailsExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                    ),
                  ),
                ),
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
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              onTap: _showAutoPermissionsDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0F6FF),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: AppColors.primary.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded,
                        size: 13, color: AppColors.primary),
                    const SizedBox(width: 5),
                    const Text(
                      'Automatic Permissions',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: AppColors.primary,
                      ),
                    ),
                  ],
                ),
              ),
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
            crossFadeState: _headerDetailsExpanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  Widget _metadataCard(List<_PropVm> props) {
    final hasMore = props.length > _metaPreviewCount;
    final visibleProps =
        _metadataExpanded ? props : props.take(_metaPreviewCount).toList();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ────────────────────────────────────────────────────────
          Row(
            children: [
              const Icon(Icons.tune_rounded, size: 15, color: AppColors.primary),
              const SizedBox(width: 6),
              const Text(
                'Metadata',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${props.length} fields',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Fields (animated expand/collapse) ─────────────────────────────
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: Column(
              children: List.generate(
                visibleProps.length * 2 - 1,
                (index) {
                  if (index.isOdd) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 10),
                      child: Divider(
                        height: 1,
                        thickness: 1.5,
                        color: Color(0xFFCBD5E1),
                      ),
                    );
                  }
                  return _propField(visibleProps[index ~/ 2]);
                },
              ),
            ),
          ),

          // ── Show more / less toggle ────────────────────────────────────────
          if (hasMore) ...[
            const SizedBox(height: 12),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 8),
            Center(
              child: GestureDetector(
                onTap: () => setState(() => _metadataExpanded = !_metadataExpanded),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: AppColors.primary.withOpacity(0.15),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _metadataExpanded
                            ? 'Show less'
                            : 'Show all ${props.length} fields',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: _metadataExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 250),
                        child: const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 16,
                          color: AppColors.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],

          // ── Assignment approval section (always visible) ───────────────────
          if (_isAssignment) ...[
            const SizedBox(height: 16),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),
            _buildAssignmentApprovalSection(props),
          ],
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PREVIEW CARD  ── file list only; signing moved to _signingCard
  // ─────────────────────────────────────────────────────────────────────────

  Widget _previewCard(ViewObject obj) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border:
                  Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined,
                    size: 16, color: AppColors.primary),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Preview file',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                if (_downloading)
                  const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: FutureBuilder<List<ObjectFile>>(
              future: _filesFuture,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                if (snap.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'Failed to load files: ${snap.error}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.red.shade700),
                    ),
                  );
                }

                final files = snap.data ?? [];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (files.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.insert_drive_file_outlined,
                                  color: Colors.grey.shade400, size: 36),
                              const SizedBox(height: 8),
                              Text(
                                'There are no files attached to this item yet.',
                                style: TextStyle(
                                    color: Colors.grey.shade600),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    // ── File rows — no signing buttons here ───────────────
                    ...files.map((f) {
                      final ext =
                          (f.extension.isEmpty ? '' : '.${f.extension}')
                              .toLowerCase();
                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: (_saving ||
                                    _downloading ||
                                    _changingWorkflow)
                                ? null
                                : () => _previewFileInApp(obj, f),
                            child: ListTile(
                              dense: true,
                              leading: FileTypeBadge(
                                  extension: f.extension, size: 36),
                              title: Text(
                                f.fileTitle.isEmpty
                                    ? 'File ${f.fileId}'
                                    : f.fileTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                  'v${f.fileVersion}${ext.isEmpty ? '' : ' • $ext'}'),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) async {
                                  final displayIdInt =
                                      int.tryParse(obj.displayId);
                                  if (displayIdInt == null) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content: Text(
                                          'Invalid object display ID: ${obj.displayId}'),
                                      backgroundColor: Colors.red.shade600,
                                    ));
                                    return;
                                  }
                                  setState(() => _downloading = true);
                                  try {
                                    final svc =
                                        context.read<MFilesService>();
                                    if (action == 'preview') {
                                      await _previewFileInApp(obj, f);
                                    } else if (action == 'open') {
                                      await svc.downloadAndOpenFile(
                                        displayObjectId: displayIdInt,
                                        classId: obj.classId,
                                        fileId: f.fileId,
                                        fileTitle: f.fileTitle,
                                        extension: f.extension,
                                        reportGuid: f.reportGuid,
                                      );
                                    } else if (action == 'download') {
                                      final savedPath =
                                          await svc.downloadAndSaveFile(
                                        displayObjectId: displayIdInt,
                                        classId: obj.classId,
                                        fileId: f.fileId,
                                        fileTitle: f.fileTitle,
                                        extension: f.extension,
                                        reportGuid: f.reportGuid,
                                      );
                                    
                                      if (!mounted) return;
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(SnackBar(
                                        content: Text(
                                            'Saved to: $savedPath'),
                                        backgroundColor:
                                            Colors.green.shade600,
                                        duration:
                                            const Duration(seconds: 4),
                                      ));
                                    } else if (action == 'convert_pdf') {
                                      _downloading = false;
                                      setState(() {});
                                      await _convertToPdf(obj, f);
                                    }
                                  } catch (e) {
                                    if (!mounted) return;
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(SnackBar(
                                      content:
                                          Text('Action failed: $e'),
                                      backgroundColor:
                                          Colors.red.shade600,
                                    ));
                                  } finally {
                                    if (mounted) {
                                      setState(
                                          () => _downloading = false);
                                    }
                                  }
                                },
                                itemBuilder: (_) {
                                  final canDownload = widget
                                          .obj.userPermission
                                          ?.readPermission ??
                                      false;
                                  return [
                                    const PopupMenuItem(
                                      value: 'preview',
                                      child: Row(children: [
                                        Icon(Icons.visibility,
                                            size: 18),
                                        SizedBox(width: 12),
                                        Text('Preview'),
                                      ]),
                                    ),
                                    const PopupMenuItem(
                                      value: 'open',
                                      child: Row(children: [
                                        Icon(Icons.open_in_new,
                                            size: 18),
                                        SizedBox(width: 12),
                                        Text('Open Externally'),
                                      ]),
                                    ),
                                    if (canDownload)
                                      const PopupMenuItem(
                                        value: 'download',
                                        child: Row(children: [
                                          Icon(Icons.download,
                                              size: 18),
                                          SizedBox(width: 12),
                                          Text('Download'),
                                        ]),
                                      ),

                                      // ── Only show for non-PDF files ──
                                      if (f.extension.trim().toLowerCase() != 'pdf')
                                        const PopupMenuItem(
                                          value: 'convert_pdf',
                                          child: Row(children: [
                                            Icon(Icons.picture_as_pdf_rounded, size: 18),
                                            SizedBox(width: 12),
                                            Text('Convert to PDF'),
                                          ]),
                                        ),
                                  ];
                                },
                                child: const Icon(Icons.more_vert,
                                    size: 18),
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _previewFileInApp(ViewObject obj, ObjectFile f) async {
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
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DocumentPreviewScreen(
          displayObjectId: displayIdInt,
          classId: obj.classId,
          fileId: f.fileId,
          fileTitle: f.fileTitle,
          extension: f.extension,
          reportGuid: f.reportGuid,
          objectTypeId: widget.obj.objectTypeId,
          canDownload: widget.obj.userPermission?.readPermission ?? false,
        ),
      ),
    );
  }

  Future<void> _convertToPdf(ViewObject obj, ObjectFile f) async {
    // Show options bottom sheet
    bool overwrite = false;
    bool separate = true;

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle bar
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(bottom: 20),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.10),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(Icons.picture_as_pdf_rounded,
                            color: AppColors.primary, size: 20),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Convert to PDF',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              'Choose conversion options',
                              style: TextStyle(
                                fontSize: 12,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Divider(height: 1, color: Colors.grey.shade100),
                  const SizedBox(height: 8),

                  // Toggle: Overwrite original
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Overwrite original file',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    subtitle: Text(
                      'Replace the existing file with the PDF version',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    value: overwrite,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setSheet(() => overwrite = v),
                  ),
                  Divider(height: 1, color: Colors.grey.shade100),

                  // Toggle: Save as separate file
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Save as separate file',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    subtitle: Text(
                      'Keep the original and add the PDF alongside it',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    value: separate,
                    activeColor: AppColors.primary,
                    onChanged: (v) => setSheet(() => separate = v),
                  ),
                  const SizedBox(height: 24),

                  // Confirm button
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 0,
                      ),
                      icon: const Icon(Icons.picture_as_pdf_rounded, size: 18),
                      label: const Text(
                        'Convert',
                        style: TextStyle(
                            fontSize: 14, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _downloading = true);
    try {
      final svc = context.read<MFilesService>();
      await svc.convertToPdf(
        objectId: widget.obj.id,
        classId: widget.obj.classId,
        fileId: f.fileId,
        overWriteOriginal: overwrite,
        separateFile: separate,
      );
      if (!mounted) return;
      setState(() => _filesFuture = _loadFiles());
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(children: [
            Icon(Icons.check_circle, color: Colors.white, size: 18),
            SizedBox(width: 8),
            Text('Converted to PDF successfully'),
          ]),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Conversion failed: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMMENTS
  // ─────────────────────────────────────────────────────────────────────────

  Future<List<ObjectComment>> _loadComments() async {
    final svc = context.read<MFilesService>();
    try {
      final items = await svc.fetchComments(
        objectId: widget.obj.id,
        objectTypeId: widget.obj.objectTypeId,
        vaultGuid: svc.vaultGuidWithBraces,
      );
      return items;
    } catch (_) {
      return <ObjectComment>[];
    }
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
            content:
                Text('Comment failed: ${svc.error ?? 'Unknown error'}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
      _commentCtrl.clear();
      _commentFocusNode.unfocus();
      if (!mounted) return;
      setState(() => _commentsFuture = _loadComments());
    } finally {
      if (mounted) setState(() => _postingComment = false);
    }
  }

  String _fmtCommentDate(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = now.difference(local);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.month}/${local.day}/${local.year}';
  }

  Widget _commentRow(ObjectComment c, {bool isPreview = false}) {
    final dateText = _fmtCommentDate(c.modifiedDate);
    final authorName = c.author.trim();
    final hasAuthor = authorName.isNotEmpty;

    final parts = authorName.split(' ').where((s) => s.isNotEmpty).toList();
    final initials = hasAuthor
        ? (parts.length >= 2
            ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
            : authorName.substring(0, authorName.length.clamp(0, 2)).toUpperCase())
        : '?';

    // Give each author a consistent subtle color based on their name
    final avatarColors = [
      const Color(0xFF6366F1), // indigo
      const Color(0xFF0EA5E9), // sky
      const Color(0xFF10B981), // emerald
      const Color(0xFFF59E0B), // amber
      const Color(0xFFEF4444), // red
      const Color(0xFF8B5CF6), // violet
      const Color(0xFF14B8A6), // teal
    ];
    final avatarColor =
        avatarColors[authorName.hashCode.abs() % avatarColors.length];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Avatar ──────────────────────────────────────────────────────
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: hasAuthor ? avatarColor : Colors.grey.shade300,
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              initials,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),

        // ── Bubble ──────────────────────────────────────────────────────
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Author + timestamp
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (hasAuthor)
                    Text(
                      authorName,
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  if (hasAuthor) const SizedBox(width: 6),
                  if (dateText.isNotEmpty)
                    Text(
                      dateText,
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              // Message bubble
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: const BorderRadius.only(
                    topRight: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                    bottomRight: Radius.circular(12),
                  ),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Text(
                  c.text,
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.45,
                    color: Color(0xFF334155),
                  ),
                  maxLines: isPreview ? 2 : null,
                  overflow:
                      isPreview ? TextOverflow.ellipsis : TextOverflow.visible,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // DATE SEPARATOR CHIP
  // ─────────────────────────────────────────────────────────────────────────
  Widget _dateSeparator(String label) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(child: Divider(height: 1, color: Colors.grey.shade200)),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10.5,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade500,
                letterSpacing: 0.3,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(child: Divider(height: 1, color: Colors.grey.shade200)),
        ],
      ),
    );
  }

  String _dateGroupLabel(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final local = dt.toLocal();
    final diff = DateTime(now.year, now.month, now.day)
        .difference(DateTime(local.year, local.month, local.day))
        .inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (diff < 7) return '${diff} days ago';
    return '${local.day}/${local.month}/${local.year}';
  }

  // ─────────────────────────────────────────────────────────────────────────
  // COMMENTS CARD  ── redesigned
  // ─────────────────────────────────────────────────────────────────────────
  Widget _commentsCard() {
    final disabled =
        _saving || _downloading || _changingWorkflow || _assigningWorkflow;

    return FutureBuilder<List<ObjectComment>>(
      future: _commentsFuture,
      builder: (context, snap) {
        final isLoading = snap.connectionState == ConnectionState.waiting;
        // Reverse so newest is at top
        final comments =
            (snap.data ?? []).reversed.toList();
        final count = comments.length;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Card header (tappable toggle) ──────────────────────────
              Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  borderRadius: BorderRadius.only(
                    topLeft: const Radius.circular(12),
                    topRight: const Radius.circular(12),
                    bottomLeft:
                        Radius.circular(_commentsExpanded ? 0 : 12),
                    bottomRight:
                        Radius.circular(_commentsExpanded ? 0 : 12),
                  ),
                  onTap: () => setState(() {
                    _commentsExpanded = !_commentsExpanded;
                    if (!_commentsExpanded) _commentFocusNode.unfocus();
                  }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        const Icon(Icons.chat_bubble_outline_rounded,
                            size: 15, color: AppColors.primary),
                        const SizedBox(width: 6),
                        Text(
                          count > 0 ? 'Comments ($count)' : 'Comments',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const Spacer(),
                        if (_postingComment)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                              height: 14,
                              width: 14,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2),
                            ),
                          ),
                        AnimatedRotation(
                          turns: _commentsExpanded ? 0.5 : 0.0,
                          duration: const Duration(milliseconds: 220),
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 20,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              // ── Collapsed preview — newest comment ─────────────────────
              if (!_commentsExpanded) ...[
                Divider(height: 1, color: Colors.grey.shade100),
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 12, horizontal: 14),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          AppColors.primary),
                    ),
                  )
                else if (comments.isEmpty)
                  InkWell(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                    onTap: () => setState(() => _commentsExpanded = true),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 14),
                      child: Row(
                        children: [
                          Icon(Icons.add_comment_outlined,
                              size: 14, color: Colors.grey.shade400),
                          const SizedBox(width: 8),
                          Text(
                            'No comments yet — tap to add one',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade400,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  InkWell(
                    borderRadius: const BorderRadius.vertical(
                        bottom: Radius.circular(12)),
                    onTap: () => setState(() => _commentsExpanded = true),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _commentRow(comments.first, isPreview: true),
                          if (count > 1) ...[
                            const SizedBox(height: 10),
                            Center(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 5),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.06),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(
                                      color:
                                          AppColors.primary.withOpacity(0.15)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '+${count - 1} more comment${count - 1 == 1 ? '' : 's'}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 12,
                                      color: AppColors.primary,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
              ],

              // ── Expanded: comment list (newest first) + input at bottom ─
              if (_commentsExpanded) ...[
                Divider(height: 1, color: Colors.grey.shade100),

                // Comment list
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                else if (snap.hasError)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'Failed to load comments: ${snap.error}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.red.shade600),
                    ),
                  )
                else if (comments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 28),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.chat_bubble_outline_rounded,
                              size: 30, color: Colors.grey.shade300),
                          const SizedBox(height: 8),
                          Text(
                            'No comments yet.\nBe the first to comment.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey.shade400,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(14, 14, 14, 14),
                    child: _buildCommentList(comments),
                  ),

                // ── Comment input — always docked at the bottom ────────────
                Divider(height: 1, color: Colors.grey.shade100),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Current user avatar
                      Container(
                        width: 30,
                        height: 30,
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: _currentUserInitials.isNotEmpty
                              ? Text(
                                  _currentUserInitials,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.person_outline,
                                  size: 16, color: Colors.white),
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Input field + send button
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Container(
                              key: _commentInputKey,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _commentInputFocused
                                      ? AppColors.primary
                                      : Colors.grey.shade200,
                                  width: _commentInputFocused ? 1.5 : 1,
                                ),
                              ),
                              child: TextField(
                                controller: _commentCtrl,
                                focusNode: _commentFocusNode,
                                enabled: !disabled && !_postingComment,
                                minLines: 1,
                                maxLines: _commentInputFocused ? 4 : 1,
                                decoration: InputDecoration(
                                  hintText: 'Add a comment…',
                                  hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 13,
                                  ),
                                  border: InputBorder.none,
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 10),
                                  isDense: true,
                                ),
                                style: const TextStyle(fontSize: 13.5),
                              ),
                            ),
                            if (_commentInputFocused) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _commentCtrl.clear();
                                      _commentFocusNode.unfocus();
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          Colors.grey.shade600,
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                    ),
                                    child: const Text('Cancel',
                                        style: TextStyle(fontSize: 12)),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton.icon(
                                    onPressed: (disabled || _postingComment)
                                        ? null
                                        : _submitComment,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: AppColors.primary,
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          Colors.grey.shade200,
                                      disabledForegroundColor:
                                          Colors.grey.shade400,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(20)),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 7),
                                      elevation: 0,
                                      textStyle: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    icon: _postingComment
                                        ? const SizedBox(
                                            width: 12,
                                            height: 12,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor:
                                                  AlwaysStoppedAnimation
                                                      <Color>(Colors.white),
                                            ),
                                          )
                                        : const Icon(
                                            Icons.send_rounded,
                                            size: 13,
                                          ),
                                    label: const Text('Send'),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

// ─────────────────────────────────────────────────────────────────────────
// COMMENT LIST WITH DATE GROUP SEPARATORS
// ─────────────────────────────────────────────────────────────────────────

Widget _buildCommentList(List<ObjectComment> comments) {
  final items = <Widget>[];
  String? lastGroup;

  for (final c in comments) {
    final group = _dateGroupLabel(c.modifiedDate);
    if (group != lastGroup) {
      items.add(_dateSeparator(group));
      lastGroup = group;
    }
    items.add(
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: _commentRow(c),
      ),
    );
  }

  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: items,
  );
}

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style:
                    TextStyle(fontSize: 12, color: Colors.grey.shade700)),
          ),
          Expanded(
            child: Text(
              v.isEmpty ? '-' : v,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PROP FIELD  ── per-field pencil + inline save/cancel
  // ─────────────────────────────────────────────────────────────────────────

  Widget _propField(_PropVm p) {
    final label = _friendlyPropLabel(p);
    final isThisFieldEditing = _editingPropId == p.id;

    // ── Lookup fields ─────────────────────────────────────────────────────
    if (_isLookup(p) || _isMultiLookup(p)) {
      final isMulti = _isMultiLookup(p);
      final displayText = _lookupDisplayText(p);

      if (isThisFieldEditing) {
        final dirtyLabels = _dirtyLookupLabels[p.id];
        final hasDirtySelection = _dirty.containsKey(p.id);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabelRow(label, p, isDirty: hasDirtySelection),
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: hasDirtySelection ? _filledFill : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: hasDirtySelection
                      ? _filledBorder
                      : Colors.grey.shade300,
                  width: hasDirtySelection ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: LookupField(
                        title: label,
                        propertyId: p.id,
                        isMultiSelect: isMulti,
                        preSelectedIds:
                            _selectedIdsForLookup(p, isMulti: isMulti),
                        preSelectedLabels: _selectedLabelsForLookup(p),
                        onSelected: (items) {
                          setState(() {
                            if (isMulti) {
                              final ids =
                                  items.map((x) => x.id).toList();
                              final labels = items
                                  .map((x) =>
                                      x.displayValue.toString())
                                  .toList();
                              if (ids.isEmpty) {
                                _dirty.remove(p.id);
                                _dirtyLookupLabels.remove(p.id);
                              } else {
                                _dirty[p.id] =
                                    p.copyWith(editedValue: ids);
                                _dirtyLookupLabels[p.id] = labels;
                              }
                            } else {
                              final id =
                                  items.isNotEmpty ? items.first.id : null;
                              if (id == null) {
                                _dirty.remove(p.id);
                                _dirtyLookupLabels.remove(p.id);
                              } else {
                                _dirty[p.id] =
                                    p.copyWith(editedValue: id);
                              }
                            }
                          });
                        },
                      ),
                    ),
                  ),
                  if (hasDirtySelection)
                    const Padding(
                      padding: EdgeInsets.only(right: 12),
                      child: Icon(Icons.check_circle_rounded,
                          color: _filledBorder, size: 18),
                    ),
                ],
              ),
            ),
            if (isMulti &&
                dirtyLabels != null &&
                dirtyLabels.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: List.generate(dirtyLabels.length, (index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(999),
                      border:
                          Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            dirtyLabels[index],
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF1E40AF),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              final currentIds =
                                  (_dirty[p.id]?.editedValue is List)
                                      ? List<int>.from(
                                          _dirty[p.id]!.editedValue
                                              as List)
                                      : <int>[];
                              final newIds = List<int>.from(currentIds)
                                ..removeAt(index);
                              final newLabels =
                                  List<String>.from(dirtyLabels)
                                    ..removeAt(index);
                              if (newIds.isEmpty) {
                                _dirty.remove(p.id);
                                _dirtyLookupLabels.remove(p.id);
                              } else {
                                _dirty[p.id] =
                                    p.copyWith(editedValue: newIds);
                                _dirtyLookupLabels[p.id] = newLabels;
                              }
                            });
                          },
                          child: Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              color: const Color(0xFF3B82F6)
                                  .withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.close,
                                size: 10, color: Color(0xFF1E40AF)),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ),
            ],
          ],
        );
      }

      return _readOnlyFieldWithPencil(
          label: label, value: displayText, prop: p);
    }

    // ── Date and timestamp fields ─────────────────────────────────────────────
    final rawCurrent = _dirty[p.id]?.editedValue ?? p.value;
    final currentText = _valueToText(rawCurrent);

    // -- Boolean fields --
    if (_isBoolean(p)) {
      // Normalise whatever the server sends to a proper bool
      bool currentBool = false;
      final raw = _dirty[p.id]?.editedValue ?? p.value;
      if (raw is bool) {
        currentBool = raw;
      } else if (raw is String) {
        currentBool = raw.toLowerCase() == 'true' || raw == '1';
      } else if (raw is num) {
        currentBool = raw != 0;
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: (_saving || _downloading || _changingWorkflow)
                ? null
                : () async {
                    // Toggle the value, mark dirty, auto-save
                    final newVal = !currentBool;
                    setState(() {
                      _dirty[p.id] = p.copyWith(editedValue: newVal);
                      _editingPropId = p.id;
                    });
                    await _saveField(p);
                  },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: currentBool
                    ? AppColors.primary.withOpacity(0.06)
                    : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: currentBool
                      ? AppColors.primary.withOpacity(0.35)
                      : Colors.grey.shade200,
                ),
              ),
              child: Row(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    width: 36,
                    height: 20,
                    decoration: BoxDecoration(
                      color: currentBool
                          ? AppColors.primary
                          : Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: AnimatedAlign(
                      duration: const Duration(milliseconds: 150),
                      alignment: currentBool
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        margin: const EdgeInsets.all(2),
                        width: 16,
                        height: 16,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    currentBool ? 'Yes' : 'No',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w500,
                      color: currentBool
                          ? AppColors.primary
                          : Colors.grey.shade600,
                    ),
                  ),
                  const Spacer(),
                  if (_saving && _editingPropId == p.id)
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.swap_horiz_rounded,
                      size: 16,
                      color: (_saving || _downloading || _changingWorkflow)
                          ? Colors.grey.shade300
                          : Colors.grey.shade400,
                    ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    // -- Date and timestamp fields --
    if (_isDate(p) || _isTimestamp(p)) {
      final isTimestamp = _isTimestamp(p);
      final displayText = currentText.trim().isNotEmpty
          ? _displayDate(currentText, includeTime: isTimestamp)
          : '';

      if (isThisFieldEditing) {
        // Show a tappable read-only tile while in editing mode;
        // the picker fires immediately so the user never types a date manually.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _fieldLabelRow(label, p, isDirty: _dirty.containsKey(p.id)),
            const SizedBox(height: 8),
            GestureDetector(
              onTap: () => _pickDate(p, includeTime: isTimestamp),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color: _filledFill,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _filledBorder, width: 1.5),
                ),
                child: Row(
                  children: [
                    Icon(
                      isTimestamp
                          ? Icons.schedule_rounded
                          : Icons.calendar_today_rounded,
                      size: 16,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        displayText.isEmpty
                            ? 'Tap to select ${isTimestamp ? 'date & time' : 'date'}'
                            : displayText,
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w500,
                          color: displayText.isEmpty
                              ? Colors.grey.shade400
                              : const Color(0xFF111827),
                        ),
                      ),
                    ),
                    Icon(Icons.edit_calendar_rounded,
                        size: 16, color: AppColors.primary.withOpacity(0.6)),
                  ],
                ),
              ),
            ),
          ],
        );
      }

      // Read-only tile: pencil icon opens the picker directly
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF475569),
                  ),
                ),
              ),
              GestureDetector(
                onTap: (_saving || _downloading || _changingWorkflow)
                    ? null
                    : () {
                        setState(() => _editingPropId = p.id);
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          _pickDate(p, includeTime: isTimestamp);
                        });
                      },
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: (_saving || _downloading || _changingWorkflow)
                        ? Colors.grey.shade100
                        : AppColors.primary.withOpacity(0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.edit_calendar_rounded,
                    size: 14,
                    color: (_saving || _downloading || _changingWorkflow)
                        ? Colors.grey.shade400
                        : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(
                  isTimestamp
                      ? Icons.schedule_rounded
                      : Icons.calendar_today_rounded,
                  size: 15,
                  color: displayText.isNotEmpty
                      ? Colors.grey.shade500
                      : Colors.grey.shade300,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    displayText.isNotEmpty ? displayText : '-',
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight: displayText.isNotEmpty
                          ? FontWeight.w500
                          : FontWeight.w400,
                      color: displayText.isNotEmpty
                          ? Colors.grey.shade700
                          : Colors.grey.shade400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return _readOnlyFieldWithPencil(
        label: label, value: currentText, prop: p);
  }

  Widget _fieldLabelRow(String label, _PropVm p, {required bool isDirty}) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
        ),
        GestureDetector(
          onTap: _cancelEditingField,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('Cancel',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade600)),
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: (isDirty && !_saving) ? () => _saveField(p) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: (isDirty && !_saving)
                  ? AppColors.primary
                  : Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _saving && _editingPropId == p.id
                ? const SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor:
                          AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    'Save',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: (isDirty && !_saving)
                          ? Colors.white
                          : Colors.grey.shade400,
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _readOnlyFieldWithPencil({
    required String label,
    required String value,
    required _PropVm prop,
  }) {
    final hasValue = value.trim().isNotEmpty;
    final busy = _saving || _downloading || _changingWorkflow;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            GestureDetector(
              onTap: busy
                  ? null
                  : () => _startEditingField(prop, _valueToText(prop.value)),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: busy
                      ? Colors.grey.shade100
                      : AppColors.primary.withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.edit_outlined,
                  size: 14,
                  color: busy ? Colors.grey.shade400 : AppColors.primary,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200, width: 1),
          ),
          child: Text(
            hasValue ? value : '—',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: hasValue ? FontWeight.w500 : FontWeight.w400,
              color:
                  hasValue ? Colors.grey.shade700 : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }
}

// ───────────── CHECKOUT BADGE CLASS ────────────────────────────────────────────────────────────────
class _CheckoutBadge extends StatelessWidget {
  final int objectId;
  final Widget child;

  const _CheckoutBadge({required this.objectId, required this.child});

  @override
  Widget build(BuildContext context) {
    final isOut = context.watch<MFilesService>().isCheckedOutLocally(objectId);
    if (!isOut) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Color(0xFF0F766E),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.drive_file_rename_outline,
              size: 10,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SEND FOR SIGNING DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _SendForSigningDialog extends StatefulWidget {
  final ObjectFile file;
  final Future<void> Function(List<String> emails) onSend;

  const _SendForSigningDialog({required this.file, required this.onSend});

  @override
  State<_SendForSigningDialog> createState() => _SendForSigningDialogState();
}

class _SendForSigningDialogState extends State<_SendForSigningDialog> {
  final _formKey = GlobalKey<FormState>();
  final List<TextEditingController> _controllers = [TextEditingController()];
  bool _sending = false;

  @override
  void dispose() {
    for (final c in _controllers) c.dispose();
    super.dispose();
  }

  void _addEmail() {
    setState(() => _controllers.add(TextEditingController()));
  }

  void _removeEmail(int index) {
    setState(() {
      _controllers[index].dispose();
      _controllers.removeAt(index);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _sending = true);
    try {
      final emails = _controllers
          .map((c) => c.text.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      await widget.onSend(emails);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(Icons.send_rounded,
                        color: AppColors.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Send for Signing',
                            style: TextStyle(
                                fontSize: 17, fontWeight: FontWeight.w700)),
                        SizedBox(height: 2),
                        Text('Enter signee email addresses',
                            style: TextStyle(
                                fontSize: 12, color: Color(0xFF64748B))),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _sending ? null : () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: Colors.grey.shade500),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Divider(color: Colors.grey.shade100, height: 1),
              const SizedBox(height: 20),
              const Text('Signee Emails',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF475569))),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.3),
                child: SingleChildScrollView(
                  child: Column(
                    children: List.generate(_controllers.length, (i) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _controllers[i],
                                keyboardType: TextInputType.emailAddress,
                                decoration: InputDecoration(
                                  hintText: 'name@example.com',
                                  hintStyle: TextStyle(
                                      color: Colors.grey.shade400,
                                      fontSize: 14),
                                  prefixIcon: Icon(Icons.email_outlined,
                                      color: Colors.grey.shade400, size: 18),
                                  filled: true,
                                  fillColor: const Color(0xFFF8FAFC),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.grey.shade200),
                                  ),
                                  enabledBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.grey.shade200),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                        color: AppColors.primary, width: 2),
                                  ),
                                  errorBorder: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                    borderSide: BorderSide(
                                        color: Colors.red.shade400),
                                  ),
                                  contentPadding:
                                      const EdgeInsets.symmetric(
                                          vertical: 13, horizontal: 14),
                                  isDense: true,
                                ),
                                validator: (v) {
                                  final val = v?.trim() ?? '';
                                  if (val.isEmpty) return 'Email is required';
                                  if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                      .hasMatch(val)) {
                                    return 'Enter a valid email';
                                  }
                                  return null;
                                },
                              ),
                            ),
                            if (_controllers.length > 1) ...[
                              const SizedBox(width: 8),
                              GestureDetector(
                                onTap: () => _removeEmail(i),
                                child: Container(
                                  width: 32,
                                  height: 32,
                                  decoration: BoxDecoration(
                                    color: Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(Icons.remove,
                                      size: 16, color: Colors.red.shade400),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
                    }),
                  ),
                ),
              ),
              TextButton.icon(
                onPressed: _sending ? null : _addEmail,
                icon: const Icon(Icons.add_circle_outline,
                    size: 16, color: AppColors.primary),
                label: const Text('Add another email',
                    style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 4, vertical: 4)),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          _sending ? null : () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      child: const Text('Cancel',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _sending ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        elevation: 0,
                      ),
                      child: _sending
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ),
                            )
                          : const Text('Send',
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// DATA CLASSES
// ─────────────────────────────────────────────────────────────────────────────

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
    final value = m.containsKey('value')
        ? m['value']
        : (m['displayValue'] ?? '');

    return _PropVm(id: id, name: name, datatype: datatype, value: value);
  }
}

class _ESignFab extends StatefulWidget {
  final VoidCallback onTap;
  final bool isBusy;
  const _ESignFab({required this.onTap, required this.isBusy});

  @override
  State<_ESignFab> createState() => _ESignFabState();
}

class _ESignFabState extends State<_ESignFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _scale = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scale,
      child: FloatingActionButton.extended(
        onPressed: widget.isBusy ? null : widget.onTap,
        backgroundColor: widget.isBusy ? Colors.grey.shade400 : AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 4,
        icon: widget.isBusy
            ? const SizedBox(
                width: 18, height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.draw_outlined, size: 20),
        label: const Text(
          'e-Sign',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
    );
  }
}