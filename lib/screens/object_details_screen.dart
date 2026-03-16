// object_details_screen.dart
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

  bool _editMode = false;
  bool _saving = false;
  bool _downloading = false;

  // Assignment completion (legacy simple button fallback)
  bool _completingAssignment = false;
  bool _assignmentCompleted = false;

  // ── Per-user approval state ──
  // Tracks which userIds have been approved in this session (optimistic UI)
  final Set<int> _approvedUserIds = {};
  // Tracks which userIds have an in-flight approval request
  final Set<int> _approvingUserIds = {};

  bool _headerDetailsExpanded = false;

  String _title = '';

  final Map<int, String> _propNameById = {};
  final Set<int> _allowedMetaPropIds = {};
  static const Set<int> _excludeMetaPropIds = {100}; // Class
  final Map<int, _PropVm> _dirty = {};

  // Store display labels for multi-select lookups so pills can show text
  final Map<int, List<String>> _dirtyLookupLabels = {};

  final ScrollController _pageScroll = ScrollController();

  // Comments
  late Future<List<ObjectComment>> _commentsFuture;
  final TextEditingController _commentCtrl = TextEditingController();
  bool _postingComment = false;
  final FocusNode _commentFocusNode = FocusNode();
  bool _commentInputFocused = false;
  bool _commentsExpanded = true;

  // ── Design constants ──
  static const _primaryBlue = Color(0xFF072F5F);
  static const _filledBorder = Color(0xFF2563EB);
  static const _filledFill = Color(0xFFF0F6FF);

  // ── Returns true when this object is an Assignment ──
  bool get _isAssignment =>
      widget.obj.classId == -100 ||
      widget.obj.classTypeName.trim().toLowerCase() == 'assignment';

  @override
  void initState() {
    super.initState();
    _title = widget.obj.title;
    _commentsFuture = _loadComments();
    _future = _loadProps();
    _filesFuture = _loadFiles();
    _workflowFuture = _loadWorkflow();
    _workflowsFuture = _loadWorkflowsForThisObject();
    _commentFocusNode.addListener(() {
      if (mounted) {
        setState(() => _commentInputFocused = _commentFocusNode.hasFocus);
      }
    });
  }

  @override
  void dispose() {
    _pageScroll.dispose();
    _commentCtrl.dispose();
    _commentFocusNode.dispose();
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

  // ─────────────────────────────────────────────────────────────────────────
  // WORKFLOW CARD HELPERS
  // ─────────────────────────────────────────────────────────────────────────

  Widget _wfRow({
    required String label,
    required Widget child,
    CrossAxisAlignment crossAxisAlignment = CrossAxisAlignment.center,
    double labelTopPadding = 2.0,
  }) {
    final isTop = crossAxisAlignment == CrossAxisAlignment.start;
    return Row(
      crossAxisAlignment: crossAxisAlignment,
      children: [
        SizedBox(
          width: 120,
          child: Padding(
            padding: EdgeInsets.only(top: isTop ? labelTopPadding : 0.0),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFF64748B),
                letterSpacing: 0.2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (child is Expanded) child else Flexible(child: child),
      ],
    );
  }

  Widget _currentStateBadge(String title) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF072F5F).withOpacity(0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFF072F5F).withOpacity(0.25)),
      ),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: Color(0xFF072F5F),
        ),
      ),
    );
  }

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
                const Icon(Icons.person_pin_outlined, size: 11, color: Color(0xFF92700A)),
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
              border: Border.all(color: const Color(0xFFFFCC02).withOpacity(0.5)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.assignment_ind_outlined, size: 15, color: Color(0xFF92700A)),
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
        color: const Color(0xFF072F5F).withOpacity(0.04),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF072F5F).withOpacity(0.12)),
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

  /// Extracts all assigned-user integer IDs from the loaded props.
  /// Looks for any Lookup / MultiSelectLookup property whose name
  /// contains "assign" (case-insensitive).
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

  /// Extracts id→displayName map for assigned users from props.
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
          (x['displayValue'] ?? x['title'] ?? x['name'])?.toString().trim() ?? '';
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

  /// Toggles approval for [userId]. Only callable for the current user.
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
              Text(!currentlyApproved ? 'Assignment approved' : 'Approval withdrawn'),
            ]),
            backgroundColor:
                !currentlyApproved ? Colors.green.shade600 : Colors.orange.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );

        // Refresh props + workflow so any state changes are reflected
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _approvingUserIds.remove(userId));
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ASSIGNMENT APPROVAL SECTION WIDGET
  //
  // Renders a per-user row with:
  //   • Avatar with initials
  //   • Name + "You" badge for current user
  //   • Approval status subtitle
  //   • Interactive circle checkbox for current user only
  //   • Read-only icon for other users
  // Falls back to the simple "Mark as Complete" button when no assigned-user
  // lookup property can be found in the object's props.
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildAssignmentApprovalSection(List<_PropVm> props) {
    final svc = context.read<MFilesService>();
    final int? currentUserId = svc.mfilesUserId;

    final assignedIds = _assignedUserIds(props);
    final labels = _assignedUserLabels(props);

    // ── Fallback: no assigned-user property found in props ──
    // Show the simple full-width "Mark as Complete" button.
    if (assignedIds.isEmpty) {
      return SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed:
              (_assignmentCompleted || _completingAssignment || _saving || _downloading)
                  ? null
                  : _markAssignmentComplete,
          style: ElevatedButton.styleFrom(
            backgroundColor: _assignmentCompleted
                ? const Color(0xFFE8F5E9)
                : const Color(0xFF072F5F),
            foregroundColor:
                _assignmentCompleted ? const Color(0xFF2E7D32) : Colors.white,
            disabledBackgroundColor: _assignmentCompleted
                ? const Color(0xFFE8F5E9)
                : Colors.grey.shade200,
            disabledForegroundColor: _assignmentCompleted
                ? const Color(0xFF2E7D32)
                : Colors.grey.shade400,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: 14),
          ),
          icon: _completingAssignment
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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

    // ── Per-user approval rows ──
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section heading
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

        // One row per assigned user
        ...assignedIds.map((uid) {
          final isMe = uid == currentUserId;
          final isApproved = _approvedUserIds.contains(uid);
          final isBusy = _approvingUserIds.contains(uid);
          final isBusyGlobal = _saving || _downloading || _completingAssignment;

          // Build display name: prefer map label, else "User <id>"
          final rawLabel = labels[uid] ?? 'User $uid';

          // Build initials from display name
          final nameParts =
              rawLabel.split(' ').where((s) => s.isNotEmpty).toList();
          final initials = nameParts.length >= 2
              ? '${nameParts.first[0]}${nameParts.last[0]}'.toUpperCase()
              : rawLabel
                  .substring(0, rawLabel.length.clamp(0, 2))
                  .toUpperCase();

          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isApproved
                  ? const Color(0xFFE8F5E9)
                  : isMe
                      ? const Color(0xFFF0F6FF)
                      : Colors.grey.shade50,
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
                // ── Avatar ──
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: isMe
                        ? const Color(0xFF072F5F)
                        : Colors.grey.shade300,
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

                // ── Name + badge + status ──
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
                                    ? const Color(0xFF072F5F)
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
                                color:
                                    const Color(0xFF072F5F).withOpacity(0.10),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Text(
                                'You',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF072F5F),
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
                              : Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Action area ──
                const SizedBox(width: 8),
                if (isBusy)
                  // Spinner while request in-flight
                  const SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else if (!isMe)
                  // Other users: read-only status icon, not tappable
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
                  // Current user: interactive toggle checkbox
                  Tooltip(
                    message: isApproved ? 'Withdraw approval' : 'Approve assignment',
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
                                    color: const Color(0xFF2563EB)
                                        .withOpacity(0.15),
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
    final canInteract = !_assigningWorkflow && !_saving && !_downloading && !_changingWorkflow;
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
              color: const Color(0xFF072F5F).withOpacity(0.04),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined, size: 16, color: Color(0xFF072F5F)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Workflow',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF072F5F),
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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Text(
                      'No workflow is assigned to this object.',
                      style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                    ),
                  ],
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
                        style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                      );
                    }
                    _selectedWorkflowId ??= workflows.first.id;
                    return Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            value: _selectedWorkflowId,
                            isExpanded: true,
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: Color(0xFF1E293B),
                            ),
                            decoration: InputDecoration(
                              labelText: 'Workflow',
                              labelStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF475569),
                              ),
                              border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              isDense: true,
                            ),
                            items: workflows
                                .map((w) => DropdownMenuItem<int>(
                                      value: w.id,
                                      child: Text(
                                        w.title,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFF1E293B),
                                        ),
                                      ),
                                    ))
                                .toList(),
                            onChanged: !canInteract
                                ? null
                                : (v) => setState(() => _selectedWorkflowId = v),
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
                                    final initialStateId =
                                        _initialStateForWorkflow(workflowId);
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
                                    if (mounted)
                                      setState(() => _assigningWorkflow = false);
                                  }
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF072F5F),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                            overlayColor: Colors.white.withOpacity(0.1),
                          ),
                          child: const Text(
                            'Assign',
                            style:
                                TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
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
      _dirtyLookupLabels.clear();
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

  /// Legacy simple-button handler — used as fallback when no assigned-user
  /// lookup property is found in the object's props.
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
            child:
                Text('Cancel', style: TextStyle(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF072F5F),
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
        Navigator.pop(context, true);
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
      if (mounted) setState(() => _completingAssignment = false);
    }
  }

  String _fmt(DateTime? dt) {
    if (dt == null) return '-';
    final local = dt.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
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
        title: Text(
          _title.isEmpty ? obj.title : _title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15, height: 1.2),
        ),
        actions: [
          IconButton(
            onPressed: (_saving || _downloading || _changingWorkflow)
                ? null
                : () {
                    setState(() {
                      _editMode = !_editMode;
                      if (!_editMode) {
                        _dirty.clear();
                        _dirtyLookupLabels.clear();
                      }
                    });
                  },
            icon: Icon(_editMode ? Icons.close : Icons.edit),
          ),
          if (_editMode)
            FutureBuilder<List<_PropVm>>(
              future: _future,
              builder: (context, snap) {
                final props = snap.data;
                final canSave =
                    _editMode && !_saving && _dirty.isNotEmpty && props != null;
                return IconButton(
                  onPressed: canSave ? () => _save(props) : null,
                  icon: _saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : const Icon(Icons.check),
                );
              },
            ),
          if (widget.obj.userPermission?.deletePermission ?? false)
            IconButton(
              onPressed: (_saving || _downloading || _changingWorkflow)
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
                  final metaProps =
                      props.where((p) => _allowedMetaPropIds.contains(p.id)).toList();
                  return RefreshIndicator(
                    onRefresh: () async {
                      setState(() {
                        _future = _loadProps();
                        _filesFuture = _loadFiles();
                        _workflowFuture = _loadWorkflow();
                        _commentsFuture = _loadComments();
                        _dirty.clear();
                        _dirtyLookupLabels.clear();
                        _editMode = false;
                        // Reset approval session state on manual refresh
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
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(8, 8, 8, 18),
                        children: [
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
                          // ── Pass the already-resolved props into _metadataCard
                          // so the assignment section can read assigned-user
                          // lookup values without a second FutureBuilder. ──
                          _metadataCard(metaProps),
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
                          const SizedBox(height: 12),
                          _previewCard(obj),
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

  Widget _buildWorkflowCardWithState(WorkflowInfo info) {
    final canChange =
        info.nextStates.isNotEmpty && !_changingWorkflow && !_saving && !_downloading;
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
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFF072F5F).withOpacity(0.04),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(12)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(
              children: [
                const Icon(Icons.account_tree_outlined,
                    size: 16, color: Color(0xFF072F5F)),
                const SizedBox(width: 6),
                const Expanded(
                  child: Text(
                    'Workflow',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF072F5F),
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
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _wfRow(
                  label: 'Workflow',
                  crossAxisAlignment: CrossAxisAlignment.start,
                  child: Text(
                    info.workflowTitle,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF0F172A),
                    ),
                    softWrap: true,
                  ),
                ),
                const SizedBox(height: 10),
                _wfRow(
                  label: 'Current state',
                  child: _currentStateBadge(info.currentStateTitle),
                ),
                if (hasDesc) ...[
                  const SizedBox(height: 16),
                  const Text(
                    'Assignment description',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF334155),
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _descriptionBox(
                      desc: info.assignmentDesc.trim(),
                      isAssignedToMe: isAssignedToMe),
                ],
                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 14),
                if (info.nextStates.isEmpty)
                  Row(
                    children: [
                      Icon(Icons.block, size: 14, color: Colors.grey.shade400),
                      const SizedBox(width: 6),
                      Text(
                        'No next steps available.',
                        style:
                            TextStyle(color: Colors.grey.shade600, fontSize: 13),
                      ),
                    ],
                  )
                else
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'ADVANCE TO',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF475569),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: DropdownButtonFormField<int>(
                              value: _selectedNextStateId,
                              isExpanded: true,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: Color(0xFF1E293B),
                              ),
                              decoration: InputDecoration(
                                labelText: 'Next state',
                                labelStyle: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF475569),
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                isDense: true,
                              ),
                              items: info.nextStates
                                  .map((s) => DropdownMenuItem<int>(
                                        value: s.id,
                                        child: Text(
                                          s.title,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Color(0xFF1E293B),
                                          ),
                                        ),
                                      ))
                                  .toList(),
                              onChanged: canChange
                                  ? (v) =>
                                      setState(() => _selectedNextStateId = v)
                                  : null,
                            ),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            onPressed:
                                (!canChange || _selectedNextStateId == null)
                                    ? null
                                    : () async {
                                        setState(
                                            () => _changingWorkflow = true);
                                        try {
                                          final svc =
                                              context.read<MFilesService>();
                                          final ok =
                                              await svc.setObjectWorkflowState(
                                            objectTypeId:
                                                widget.obj.objectTypeId,
                                            objectId: widget.obj.id,
                                            workflowId: info.workflowId,
                                            stateId: _selectedNextStateId!,
                                          );
                                          if (!ok) {
                                            if (!mounted) return;
                                            ScaffoldMessenger.of(context)
                                                .showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                    'Workflow update failed: ${svc.error ?? 'Unknown'}'),
                                                backgroundColor:
                                                    Colors.red.shade600,
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
                                          if (mounted)
                                            setState(
                                                () => _changingWorkflow = false);
                                        }
                                      },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF072F5F),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                            child: const Text(
                              'Apply',
                              style: TextStyle(
                                  fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
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
                  ? FileTypeBadge(extension: firstFile.extension, size: 36)
                  : Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: const Color(0xFF072F5F).withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          Icons.description_outlined,
                          size: 20,
                          color: Color(0xFF072F5F),
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
          Row(
            children: [
              const Expanded(
                child: Text('Metadata',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              Text(
                _editMode ? 'Editing' : 'Read-only',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (props.isNotEmpty)
            Column(
              children: List.generate(
                props.length * 2 - 1,
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
                  return _propField(props[index ~/ 2]);
                },
              ),
            ),

          // ── Assignment approval section ──
          // Only shown for assignment objects. Receives the already-loaded
          // props so no extra async fetch is needed.
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

  Widget _propField(_PropVm p) {
    final label = _friendlyPropLabel(p);

    if (_isLookup(p) || _isMultiLookup(p)) {
      final isMulti = _isMultiLookup(p);
      final displayText = _lookupDisplayText(p);
      final hasValue = displayText.trim().isNotEmpty;

      if (_editMode) {
        final dirtyLabels = _dirtyLookupLabels[p.id];
        final hasDirtySelection = _dirty.containsKey(p.id);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569),
                ),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              decoration: BoxDecoration(
                color: hasDirtySelection ? _filledFill : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color:
                      hasDirtySelection ? _filledBorder : Colors.grey.shade300,
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
                              final ids = items.map((x) => x.id).toList();
                              final labels =
                                  items.map((x) => x.displayValue.toString()).toList();
                              if (ids.isEmpty) {
                                _dirty.remove(p.id);
                                _dirtyLookupLabels.remove(p.id);
                              } else {
                                _dirty[p.id] = p.copyWith(editedValue: ids);
                                _dirtyLookupLabels[p.id] = labels;
                              }
                            } else {
                              final id =
                                  items.isNotEmpty ? items.first.id : null;
                              if (id == null) {
                                _dirty.remove(p.id);
                                _dirtyLookupLabels.remove(p.id);
                              } else {
                                _dirty[p.id] = p.copyWith(editedValue: id);
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
            if (isMulti && dirtyLabels != null && dirtyLabels.isNotEmpty) ...[
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
                        Text(
                          dirtyLabels[index],
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1E40AF),
                          ),
                        ),
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () {
                            setState(() {
                              final currentIds =
                                  (_dirty[p.id]?.editedValue is List)
                                      ? List<int>.from(
                                          _dirty[p.id]!.editedValue as List)
                                      : <int>[];
                              final newIds =
                                  List<int>.from(currentIds)..removeAt(index);
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
                              color: const Color(0xFF3B82F6).withOpacity(0.2),
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
            ] else if (!isMulti ||
                (dirtyLabels == null || dirtyLabels.isEmpty)) ...[
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: hasValue
                    ? Row(
                        children: [
                          Icon(Icons.check_circle_outline,
                              size: 13, color: Colors.green.shade600),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              'Current: $displayText',
                              style: TextStyle(
                                  fontSize: 11.5, color: Colors.grey.shade600),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      )
                    : Text(
                        'No value — tap above to select',
                        style: TextStyle(
                            fontSize: 11.5, color: Colors.grey.shade400),
                      ),
              ),
            ],
          ],
        );
      }

      return _readOnlyField(label: label, value: displayText);
    }

    final rawCurrent = _dirty[p.id]?.editedValue ?? p.value;
    final currentText = _valueToText(rawCurrent);

    if (_editMode) {
      final isDirty = _dirty.containsKey(p.id);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475569),
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            child: TextFormField(
              initialValue: currentText,
              style: const TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w500,
                color: Color(0xFF111827),
              ),
              decoration: InputDecoration(
                hintText: 'Enter ${label.toLowerCase()}',
                hintStyle:
                    TextStyle(color: Colors.grey.shade400, fontSize: 14),
                isDense: true,
                filled: true,
                fillColor: isDirty ? _filledFill : Colors.grey.shade50,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: isDirty
                      ? const BorderSide(color: _filledBorder, width: 1.5)
                      : BorderSide(color: Colors.grey.shade200),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade200),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _primaryBlue, width: 2),
                ),
                suffixIcon: isDirty
                    ? const Icon(Icons.check_circle_rounded,
                        color: _filledBorder, size: 18)
                    : null,
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
          ),
        ],
      );
    }

    return _readOnlyField(label: label, value: currentText);
  }

  Widget _readOnlyField({required String label, required String value}) {
    final hasValue = value.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: Color(0xFF475569),
            ),
          ),
        ),
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
              fontWeight:
                  hasValue ? FontWeight.w500 : FontWeight.w400,
              color: hasValue ? Colors.grey.shade700 : Colors.grey.shade400,
            ),
          ),
        ),
      ],
    );
  }

  Widget _previewCard(ViewObject obj) {
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
          Row(
            children: [
              const Expanded(
                child: Text('Preview',
                    style:
                        TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (_downloading)
                const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(strokeWidth: 2)),
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
                return Padding(
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
                          style:
                              TextStyle(color: Colors.grey.shade600),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Column(
                children: files.map((f) {
                  final ext =
                      (f.extension.isEmpty ? '' : '.${f.extension}')
                          .toLowerCase();
                  return Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: (_saving || _downloading || _changingWorkflow)
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
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                        'Invalid object display ID: ${obj.displayId}'),
                                    backgroundColor: Colors.red.shade600,
                                  ),
                                );
                                return;
                              }
                              setState(() => _downloading = true);
                              try {
                                final svc = context.read<MFilesService>();
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
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content:
                                          Text('Saved to: $savedPath'),
                                      backgroundColor:
                                          Colors.green.shade600,
                                      duration:
                                          const Duration(seconds: 4),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content:
                                        Text('Action failed: $e'),
                                    backgroundColor: Colors.red.shade600,
                                  ),
                                );
                              } finally {
                                if (mounted)
                                  setState(() => _downloading = false);
                              }
                            },
                            itemBuilder: (_) {
                              final canDownload =
                                  widget.obj.userPermission
                                          ?.readPermission ??
                                      false;
                              return [
                                const PopupMenuItem(
                                  value: 'preview',
                                  child: Row(
                                    children: [
                                      Icon(Icons.visibility, size: 18),
                                      SizedBox(width: 12),
                                      Text('Preview'),
                                    ],
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'open',
                                  child: Row(
                                    children: [
                                      Icon(Icons.open_in_new, size: 18),
                                      SizedBox(width: 12),
                                      Text('Open Externally'),
                                    ],
                                  ),
                                ),
                                if (canDownload)
                                  const PopupMenuItem(
                                    value: 'download',
                                    child: Row(
                                      children: [
                                        Icon(Icons.download, size: 18),
                                        SizedBox(width: 12),
                                        Text('Download'),
                                      ],
                                    ),
                                  ),
                              ];
                            },
                            child: const Icon(Icons.more_vert, size: 18),
                          ),
                        ),
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

  Future<void> _previewFileInApp(ViewObject obj, ObjectFile f) async {
    final displayIdInt = int.tryParse(obj.displayId);
    if (displayIdInt == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text('Invalid object display ID: ${obj.displayId}'),
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
          canDownload:
              widget.obj.userPermission?.readPermission ?? false,
        ),
      ),
    );
  }

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
            content: Text(
                'Comment failed: ${svc.error ?? 'Unknown error'}'),
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

  Widget _commentRow(ObjectComment c) {
    final dateText = _fmtCommentDate(c.modifiedDate);
    final authorName = c.author.trim();
    final hasAuthor = authorName.isNotEmpty;

    Widget avatarWidget;
    if (hasAuthor) {
      final parts =
          authorName.split(' ').where((s) => s.isNotEmpty).toList();
      final initials = parts.length >= 2
          ? '${parts.first[0]}${parts.last[0]}'.toUpperCase()
          : authorName
              .substring(0, authorName.length.clamp(0, 2))
              .toUpperCase();
      avatarWidget = Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(
            color: Color(0xFF072F5F), shape: BoxShape.circle),
        child: Center(
          child: Text(initials,
              style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white)),
        ),
      );
    } else {
      avatarWidget = Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
            color: const Color(0xFF072F5F).withOpacity(0.08),
            shape: BoxShape.circle),
        child: const Center(
            child: Icon(Icons.person_outline,
                size: 15, color: Color(0xFF072F5F))),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        avatarWidget,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (hasAuthor) ...[
                    Text(authorName,
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B))),
                    const SizedBox(width: 6),
                  ],
                  if (dateText.isNotEmpty)
                    Text(dateText,
                        style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                            fontWeight: FontWeight.w400)),
                ],
              ),
              const SizedBox(height: 3),
              Text(c.text,
                  style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: Color(0xFF1E293B))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _commentsCard() {
    final disabled =
        _saving || _downloading || _changingWorkflow || _assigningWorkflow;
    return FutureBuilder<List<ObjectComment>>(
      future: _commentsFuture,
      builder: (context, snap) {
        final isLoading =
            snap.connectionState == ConnectionState.waiting;
        final comments = snap.data ?? [];
        final count = comments.length;
        final latestComment =
            comments.isNotEmpty ? comments.last : null;

        return Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                    if (!_commentsExpanded)
                      _commentFocusNode.unfocus();
                  }),
                  child: Padding(
                    padding:
                        const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.chat_bubble_outline,
                            size: 16, color: Color(0xFF072F5F)),
                        const SizedBox(width: 6),
                        Text(
                          count > 0
                              ? 'Comments ($count)'
                              : 'Comments',
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        if (_postingComment)
                          const Padding(
                            padding: EdgeInsets.only(right: 8),
                            child: SizedBox(
                                height: 14,
                                width: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2)),
                          ),
                        AnimatedRotation(
                          turns: _commentsExpanded ? 0.5 : 0.0,
                          duration:
                              const Duration(milliseconds: 200),
                          child: Icon(Icons.keyboard_arrow_down,
                              size: 20,
                              color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!_commentsExpanded) ...[
                Divider(height: 1, color: Colors.grey.shade200),
                if (isLoading)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 14, horizontal: 12),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      backgroundColor: Colors.grey.shade100,
                      valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFF072F5F)),
                    ),
                  )
                else if (latestComment == null)
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12)),
                      onTap: () =>
                          setState(() => _commentsExpanded = true),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 14),
                        child: Row(
                          children: [
                            Icon(Icons.edit_outlined,
                                size: 14,
                                color: Colors.grey.shade400),
                            const SizedBox(width: 8),
                            Text(
                              'No comments yet — tap to add one',
                              style: TextStyle(
                                  fontSize: 12.5,
                                  color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                else
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(12)),
                      onTap: () =>
                          setState(() => _commentsExpanded = true),
                      child: Padding(
                        padding:
                            const EdgeInsets.fromLTRB(12, 10, 12, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _commentRow(latestComment),
                            if (count > 1) ...[
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const SizedBox(width: 38),
                                  Text(
                                    'View all $count comments',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFF2563EB),
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 13,
                                      color: Color(0xFF2563EB)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
              if (_commentsExpanded) ...[
                Divider(height: 1, color: Colors.grey.shade200),
                Padding(
                  padding:
                      const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color:
                              const Color(0xFF072F5F).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.person_outline,
                              size: 18,
                              color: Color(0xFF072F5F)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.end,
                          children: [
                            TextField(
                              controller: _commentCtrl,
                              focusNode: _commentFocusNode,
                              enabled:
                                  !disabled && !_postingComment,
                              minLines: 1,
                              maxLines:
                                  _commentInputFocused ? 4 : 1,
                              decoration: InputDecoration(
                                hintText: 'Add a comment…',
                                hintStyle: TextStyle(
                                    color: Colors.grey.shade400,
                                    fontSize: 13),
                                filled: false,
                                border: InputBorder.none,
                                enabledBorder:
                                    UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color:
                                                Colors.grey.shade300)),
                                focusedBorder:
                                    const UnderlineInputBorder(
                                        borderSide: BorderSide(
                                            color: Color(0xFF072F5F),
                                            width: 1.5)),
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        vertical: 8),
                                isDense: true,
                              ),
                              style: const TextStyle(fontSize: 13.5),
                            ),
                            if (_commentInputFocused) ...[
                              const SizedBox(height: 8),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.end,
                                children: [
                                  TextButton(
                                    onPressed: () {
                                      _commentCtrl.clear();
                                      _commentFocusNode.unfocus();
                                    },
                                    style: TextButton.styleFrom(
                                      foregroundColor:
                                          Colors.grey.shade600,
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 6),
                                      shape:
                                          RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(20)),
                                    ),
                                    child: const Text('Cancel',
                                        style: TextStyle(
                                            fontSize: 12)),
                                  ),
                                  const SizedBox(width: 6),
                                  ElevatedButton(
                                    onPressed:
                                        (disabled || _postingComment)
                                            ? null
                                            : _submitComment,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          const Color(0xFF072F5F),
                                      foregroundColor: Colors.white,
                                      disabledBackgroundColor:
                                          Colors.grey.shade200,
                                      disabledForegroundColor:
                                          Colors.grey.shade400,
                                      shape:
                                          RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius
                                                      .circular(20)),
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 7),
                                      elevation: 0,
                                      textStyle: const TextStyle(
                                          fontSize: 12,
                                          fontWeight:
                                              FontWeight.w600),
                                    ),
                                    child: const Text('Comment'),
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
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                        child: CircularProgressIndicator(
                            strokeWidth: 2)),
                  )
                else if (snap.hasError)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 12),
                    child: Text(
                        'Failed to load comments: ${snap.error}',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade700),
                        textAlign: TextAlign.center),
                  )
                else if (comments.isEmpty)
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(vertical: 20),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.chat_bubble_outline,
                              size: 32,
                              color: Colors.grey.shade300),
                          const SizedBox(height: 6),
                          Text('No comments yet. Be the first!',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500)),
                        ],
                      ),
                    ),
                  )
                else
                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(12, 4, 12, 12),
                    child: Column(
                      children: [
                        Padding(
                          padding:
                              const EdgeInsets.only(bottom: 12),
                          child: Divider(
                              height: 1,
                              color: Colors.grey.shade100),
                        ),
                        ...comments.map((c) => Padding(
                              padding:
                                  const EdgeInsets.only(bottom: 14),
                              child: _commentRow(c),
                            )),
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

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(k,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey.shade700)),
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

    final datatype =
        rawDatatype.replaceAll('MFDataType', 'MFDatatype');
    final value = m.containsKey('value')
        ? m['value']
        : (m['displayValue'] ?? '');

    return _PropVm(id: id, name: name, datatype: datatype, value: value);
  }
}