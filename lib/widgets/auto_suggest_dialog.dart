// ============================================================
// AUTO-SUGGEST FEATURE
// File: lib/widgets/auto_suggest_dialog.dart
// ============================================================

import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

// ── Data model for a single suggestion ──────────────────────

class SuggestedField {
  final int propertyId;
  final String propertyTitle;
  final String displayValue; // human-readable label
  final dynamic rawValue;    // the actual value to pre-fill
  final String propertyType; // e.g. 'MFDatatypeLookup'

  const SuggestedField({
    required this.propertyId,
    required this.propertyTitle,
    required this.displayValue,
    required this.rawValue,
    required this.propertyType,
  });
}

// ── Core helper: extract suggestions from GetObjectViewProps ─

/// Compares the props returned by GetObjectViewProps against the
/// property IDs present in the current form and returns only those
/// that match and carry a non-empty value.
///
/// [fetchedProps]    – raw list from GetObjectViewProps response
/// [formPropertyIds] – set of prop IDs actually shown in the form
List<SuggestedField> extractSuggestions({
  required List<Map<String, dynamic>> fetchedProps,
  required Set<int> formPropertyIds,
}) {
  final suggestions = <SuggestedField>[];

  for (final prop in fetchedProps) {
    // ── 1. Resolve property ID ──────────────────────────────
    // Your API returns 'id' (confirmed from web debug logs).
    // We try all known casings so this is resilient to backend changes.
    final id = _toInt(
      prop['id'] ??           // ← primary key your API uses
      prop['propId'] ??
      prop['propertyId'] ??
      prop['PropertyId'] ??
      prop['property_id'],
    );
    if (id == null || id <= 0) continue;
    if (!formPropertyIds.contains(id)) continue;
    if (_isSystemProp(id)) continue;

    // ── 2. Resolve property type ────────────────────────────
    // Your API returns 'datatype' (lowercase) — confirmed from web logs:
    // {id: 1151, value: '8/1/2025', datatype: 'MFDatatypeDate', ...}
    final type = (prop['datatype'] ??       // ← primary (your API)
                  prop['dataType'] ??
                  prop['DataType'] ??
                  prop['propertytype'] ??
                  prop['propertyType'] ??
                  prop['PropertyType'] ??
                  '')
        .toString();

    // ── 3. Extract the machine-readable value ───────────────
    final rawValue = _extractRawValue(prop, type);
    if (rawValue == null) continue;

    // ── 4. Build display string ─────────────────────────────
    final display = _buildDisplayValue(prop, rawValue, type);
    if (display.isEmpty) continue;

    // ── 5. Resolve property title ───────────────────────────
    // Your API returns 'propName' — confirmed from web logs.
    final title = (prop['propName'] ??      // ← primary (your API)
                   prop['propertyName'] ??
                   prop['PropertyName'] ??
                   prop['title'] ??
                   prop['Title'] ??
                   'Property $id')
        .toString();

    suggestions.add(SuggestedField(
      propertyId: id,
      propertyTitle: title,
      displayValue: display,
      rawValue: rawValue,
      propertyType: type,
    ));
  }

  return suggestions;
}

// ── Private helpers ──────────────────────────────────────────

// System / automatic prop IDs that should never be pre-filled.
const _systemPropIds = {0, 20, 21, 22, 23, 24, 25, 26, 27, 38, 39, 41, 44, 81, 100};
//                                                    ^^  ^^  ^^  ^^  ^^
//                        Workflow, State, Assignment desc, Assigned-to, Accessed-by-me
// Add any other system props your vault uses here.

bool _isSystemProp(int id) => _systemPropIds.contains(id);

int? _toInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse('$v');
}

/// Pulls the machine-readable value from whatever shape the API returns.
dynamic _extractRawValue(Map<String, dynamic> prop, String type) {
  final raw = prop['value'] ??
              prop['Value'] ??
              prop['typedValue'] ??
              prop['TypedValue'];

  if (raw == null) return null;

  final typeNorm = type.toLowerCase();

  // ── MultiSelectLookup ──────────────────────────────────────
  if (typeNorm.contains('multiselectlookup') ||
      typeNorm.contains('multi_select')) {
    if (raw is List) {
      if (raw.isEmpty) return null; // empty list = no value to suggest
      final ids = raw
          .map((e) => e is Map
              ? _toInt(e['id'] ?? e['Id'] ?? e['lookupId'])
              : _toInt(e))
          .whereType<int>()
          .toList();
      return ids.isEmpty ? null : ids;
    }
    if (raw is String && raw.contains(',')) {
      final ids = raw
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .toList();
      return ids.isEmpty ? null : ids;
    }
    final single = _toInt(raw);
    return single != null ? [single] : null;
  }

  // ── Single Lookup ──────────────────────────────────────────
  if (typeNorm.contains('lookup')) {
    if (raw is List) {
      if (raw.isEmpty) return null;
      final first = raw.first;
      return first is Map
          ? _toInt(first['id'] ?? first['Id'] ?? first['lookupId'])
          : _toInt(first);
    }
    if (raw is Map) {
      return _toInt(raw['id'] ?? raw['Id'] ?? raw['lookupId']);
    }
    return _toInt(raw);
  }

  // ── Boolean ───────────────────────────────────────────────
  if (typeNorm.contains('boolean')) {
    if (raw is bool) return raw;
    final s = raw.toString().toLowerCase().trim();
    if (s.isEmpty) return null;
    return s == 'true' || s == '1' || s == 'yes';
  }

  // ── Date ──────────────────────────────────────────────────
  if (typeNorm.contains('date') && !typeNorm.contains('timestamp')) {
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    // Normalise M/d/yyyy → yyyy-MM-dd if needed
    if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}').hasMatch(s)) {
      try {
        final parts = s.split('/');
        final m = int.parse(parts[0]);
        final d = int.parse(parts[1]);
        final y = int.parse(parts[2].split(' ')[0]);
        return '${y.toString().padLeft(4, '0')}-'
               '${m.toString().padLeft(2, '0')}-'
               '${d.toString().padLeft(2, '0')}';
      } catch (_) {}
    }
    if (s.length >= 10) return s.substring(0, 10); // yyyy-MM-dd
    return null;
  }

  // ── Timestamp: skip — can't pre-fill system timestamps ────
  if (typeNorm.contains('timestamp')) return null;

  // ── Text / Integer / Floating / default ───────────────────
  final s = raw.toString().trim();
  return s.isEmpty ? null : s;
}

String _buildDisplayValue(
    Map<String, dynamic> prop, dynamic rawValue, String type) {
  // Prefer a pre-built display string from the API
  final apiDisplay = prop['displayValue'] ??
      prop['DisplayValue'] ??
      prop['lookupDisplayValue'];
  if (apiDisplay is String && apiDisplay.trim().isNotEmpty) {
    return apiDisplay.trim();
  }

  final typeNorm = type.toLowerCase();

  if (typeNorm.contains('boolean')) {
    return rawValue == true ? 'Yes' : 'No';
  }

  if (rawValue is List) {
    if (rawValue.isEmpty) return '';
    return rawValue.map((e) => e.toString()).join(', ');
  }

  return rawValue.toString().trim();
}

// ── "Checking for suggestions…" loading dialog ───────────────

Future<void> showCheckingDialog(BuildContext context) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _CheckingDialog(),
  );
}

class _CheckingDialog extends StatefulWidget {
  const _CheckingDialog();
  @override
  State<_CheckingDialog> createState() => _CheckingDialogState();
}

class _CheckingDialogState extends State<_CheckingDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 60),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _AnimatedDots(controller: _ctrl),
            const SizedBox(height: 20),
            const Text(
              'Checking for suggestions...',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1E293B),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AnimatedDots extends AnimatedWidget {
  const _AnimatedDots({required AnimationController controller})
      : super(listenable: controller);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as AnimationController).value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (i) {
        final opacity = ((t * 3 - i) % 3 / 2).clamp(0.2, 1.0);
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Opacity(
            opacity: opacity,
            child: const CircleAvatar(
              radius: 5,
              backgroundColor: AppColors.primary,
            ),
          ),
        );
      }),
    );
  }
}

// ── Suggested Properties dialog ──────────────────────────────

/// Shows the suggestions dialog and returns the list of fields
/// the user chose to apply, or null if dismissed.
Future<List<SuggestedField>?> showSuggestionsDialog({
  required BuildContext context,
  required List<SuggestedField> suggestions,
  required String sourceLabel,
}) async {
  if (suggestions.isEmpty) return null;

  return showDialog<List<SuggestedField>>(
    context: context,
    builder: (ctx) => _SuggestionsDialog(
      suggestions: suggestions,
      sourceLabel: sourceLabel,
    ),
  );
}

class _SuggestionsDialog extends StatefulWidget {
  final List<SuggestedField> suggestions;
  final String sourceLabel;

  const _SuggestionsDialog({
    required this.suggestions,
    required this.sourceLabel,
  });

  @override
  State<_SuggestionsDialog> createState() => _SuggestionsDialogState();
}

class _SuggestionsDialogState extends State<_SuggestionsDialog> {
  late final Set<int> _checked;

  @override
  void initState() {
    super.initState();
    // All checked by default — mirrors web behaviour
    _checked = widget.suggestions.map((s) => s.propertyId).toSet();
  }

  bool get _allChecked => _checked.length == widget.suggestions.length;
  bool get _noneChecked => _checked.isEmpty;

  void _toggleAll(bool select) {
    setState(() {
      if (select) {
        _checked.addAll(widget.suggestions.map((s) => s.propertyId));
      } else {
        _checked.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final selectedCount = _checked.length;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 48),
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.75,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ─────────────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Suggested Properties',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'From: ${widget.sourceLabel}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white70,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),

            // ── Sub-header ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Text(
                'Select which values to copy into the form:',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: Colors.grey.shade600,
                ),
              ),
            ),

            // ── Suggestion rows ─────────────────────────────
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                itemCount: widget.suggestions.length,
                separatorBuilder: (_, __) => const Divider(
                  height: 1,
                  color: Color(0xFFF1F5F9),
                ),
                itemBuilder: (_, i) {
                  final s = widget.suggestions[i];
                  final checked = _checked.contains(s.propertyId);
                  return _SuggestionRow(
                    field: s,
                    checked: checked,
                    onToggle: (v) {
                      setState(() {
                        if (v) {
                          _checked.add(s.propertyId);
                        } else {
                          _checked.remove(s.propertyId);
                        }
                      });
                    },
                  );
                },
              ),
            ),

            // ── Footer actions ──────────────────────────────
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(color: Colors.grey.shade100),
                ),
              ),
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => _toggleAll(!_allChecked),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                    ),
                    child: Text(
                      _allChecked ? 'None' : 'Select All',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),

                  const Spacer(),

                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey.shade600,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    child: const Text(
                      'Dismiss',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  ElevatedButton(
                    onPressed: _noneChecked
                        ? null
                        : () {
                            final chosen = widget.suggestions
                                .where((s) =>
                                    _checked.contains(s.propertyId))
                                .toList();
                            Navigator.pop(context, chosen);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade200,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      elevation: 0,
                    ),
                    child: Text(
                      selectedCount > 0
                          ? 'Apply ($selectedCount)'
                          : 'Apply',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
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
}

class _SuggestionRow extends StatelessWidget {
  final SuggestedField field;
  final bool checked;
  final ValueChanged<bool> onToggle;

  const _SuggestionRow({
    required this.field,
    required this.checked,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => onToggle(!checked),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Row(
          children: [
            // Checkbox
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: checked ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: checked ? AppColors.primary : Colors.grey.shade300,
                  width: 1.5,
                ),
              ),
              child: checked
                  ? const Icon(Icons.check, size: 14, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 14),

            // Property title + value pill
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      field.propertyTitle,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    flex: 5,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: checked
                            ? const Color(0xFFEFF6FF)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: checked
                              ? const Color(0xFFBFDBFE)
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: Text(
                        field.displayValue,
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: checked
                              ? const Color(0xFF1E40AF)
                              : Colors.grey.shade600,
                        ),
                      ),
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
}