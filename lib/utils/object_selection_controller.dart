// lib/utils/object_selection_controller.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../models/view_object.dart';

/// Summarises the outcome of a batch action across multiple objects.
class BatchActionResult {
  final int succeeded;
  final int skipped;
  final int failed;
  final String? skipReason;

  const BatchActionResult({
    required this.succeeded,
    required this.skipped,
    required this.failed,
    this.skipReason,
  });

  bool get hasSkips => skipped > 0;
  bool get hasFails => failed > 0;
  bool get allSucceeded => failed == 0 && skipped == 0;

  String toToastMessage(String actionPast) {
    final parts = <String>[];
    if (succeeded > 0) parts.add('$succeeded $actionPast');
    if (skipped > 0) {
      final reason = skipReason != null ? ' — $skipReason' : '';
      parts.add('$skipped skipped$reason');
    }
    if (failed > 0) parts.add('$failed failed');
    return parts.join(', ');
  }
}

/// Per-screen-instance selection state. Create one per Scaffold that needs
/// multi-select; dispose it in the screen's dispose().
class ObjectSelectionController extends ChangeNotifier {
  final _selected = <int, ViewObject>{};
  bool _selectionMode = false;

  bool get selectionMode => _selectionMode;
  int get count => _selected.length;
  List<ViewObject> get selectedObjects => _selected.values.toList();
  Set<int> get selectedIds => _selected.keys.toSet();

  bool isSelected(int id) => _selected.containsKey(id);

  // ── Entry / exit ──────────────────────────────────────────────────────────

  void enterSelectionMode(ViewObject first) {
    HapticFeedback.mediumImpact();
    _selectionMode = true;
    _selected[first.id] = first;
    notifyListeners();
  }

  void exitSelectionMode() {
    _selectionMode = false;
    _selected.clear();
    notifyListeners();
  }

  // ── Toggle ────────────────────────────────────────────────────────────────

  void toggle(ViewObject obj) {
    if (_selected.containsKey(obj.id)) {
      _selected.remove(obj.id);
      // Auto-exit if nothing left selected
      if (_selected.isEmpty) _selectionMode = false;
    } else {
      _selected[obj.id] = obj;
    }
    notifyListeners();
  }

  // ── Checkout state helpers ────────────────────────────────────────────────

  /// True only if every selected object shares the same checkout state.
  bool get isUniformCheckoutState {
    if (_selected.isEmpty) return true;
    final first = _selected.values.first.isCheckedOut;
    return _selected.values.every((o) => o.isCheckedOut == first);
  }

  /// True if all selected objects are currently checked out.
  bool get allCheckedOut =>
      _selected.isNotEmpty && _selected.values.every((o) => o.isCheckedOut);

  /// True if any selected object is checked out.
  bool get anyCheckedOut => _selected.values.any((o) => o.isCheckedOut);

  /// True if all selected objects are NOT checked out.
  bool get noneCheckedOut => _selected.values.every((o) => !o.isCheckedOut);

  // ── Document helpers ──────────────────────────────────────────────────────

  /// True if every selected object is a document (objectTypeId == 0).
  bool get allDocuments =>
      _selected.isNotEmpty &&
      _selected.values.every((o) => o.objectTypeId == 0);

  /// True if any selected object is a non-PDF document.
  bool hasNonPdfDocuments(Map<int, String> extCache) {
    return _selected.values.any((o) {
      if (o.objectTypeId != 0) return false;
      final ext = (extCache[o.id] ?? '').toLowerCase();
      return ext != 'pdf' && ext.isNotEmpty;
    });
  }

  // ── Version history ───────────────────────────────────────────────────────

  /// Version History is only available for exactly one selected object.
  bool get canShowVersionHistory => _selected.length == 1;

  ViewObject? get singleSelectedObject =>
      _selected.length == 1 ? _selected.values.first : null;
}