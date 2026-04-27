// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/widgets/lookup_field.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
class TemplateFormScreen extends StatefulWidget {
  final int classId;
  final String className;
  final int templateObjectId;
  final String templateTitle;

  const TemplateFormScreen({
    super.key,
    required this.classId,
    required this.className,
    required this.templateObjectId,
    required this.templateTitle,
  });

  @override
  State<TemplateFormScreen> createState() => _TemplateFormScreenState();
}

class _TemplateFormScreenState extends State<TemplateFormScreen> {
  List<Map<String, dynamic>> _props = [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;

  static const _systemPropIds = {20, 21, 23, 25};
  static const _primaryBlue = AppColors.primary;
  static const _filledBorder = Color(0xFF2563EB);
  static const _filledFill = Color(0xFFF0F6FF);

  static final _uiDateFmt = DateFormat('dd MMM yyyy');
  static final _apiDateFmt = DateFormat('yyyy-MM-dd');

  final Map<int, TextEditingController> _controllers = {};
  final Map<int, dynamic> _values = {};
  final Map<int, List<dynamic>> _selectedLookupItems = {};

  @override
  void initState() {
    super.initState();
    _loadProps();
  }

  @override
  void dispose() {
    for (final c in _controllers.values) c.dispose();
    super.dispose();
  }

  bool _isReadOnly(Map<String, dynamic> prop) {
    final id = prop['propId'] as int;
    final isAutomatic = prop['isAutomatic'] as bool? ?? false;
    final canEdit = prop['userPermission']?['editPermission'] as bool? ?? true;
    return isAutomatic || _systemPropIds.contains(id) || !canEdit;
  }

  bool _isVisible(Map<String, dynamic> prop) {
    return !(prop['isHidden'] as bool? ?? false);
  }

  Future<void> _loadProps() async {
    final service = context.read<MFilesService>();
    final vaultGuid = service.selectedVault?.guid ?? '';
    setState(() { _loading = true; _error = null; });

    try {
      final data = await service.fetchClassTemplateProps(
        vaultGuid: vaultGuid,
        classId: widget.classId,
        objectId: widget.templateObjectId,
        userId: service.currentUserId,
      );

      for (final prop in data) {
        final id = prop['propId'] as int;
        final value = (prop['value'] ?? '').toString();
        final type = prop['propertytype'] as String? ?? '';
        if (_isReadOnly(prop)) continue;

        switch (type) {
          case 'MFDatatypeText':
          case 'MFDatatypeMultiLineText':
            _controllers[id] = TextEditingController(text: value);
            break;
          case 'MFDatatypeInteger':
            _controllers[id] = TextEditingController(
              text: value.isNotEmpty && int.tryParse(value.split('.').first) != null
                  ? value.split('.').first : '',
            );
            break;
          case 'MFDatatypeDate':
            _values[id] = _normaliseDateValue(value);
            break;
          case 'MFDatatypeLookup':
          case 'MFDatatypeMultiSelectLookup':
            _values[id] = null;
            break;
          default:
            _controllers[id] = TextEditingController(text: value);
            break;
        }
      }

      setState(() { _props = data; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
    }
  }

  String? _normaliseDateValue(String raw) {
    if (raw.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) return raw.substring(0, 10);
    try {
      final parts = raw.split('/');
      if (parts.length == 3) {
        final m = int.parse(parts[0]);
        final d = int.parse(parts[1]);
        final y = int.parse(parts[2].split(' ')[0]);
        return '${y.toString().padLeft(4,'0')}-${m.toString().padLeft(2,'0')}-${d.toString().padLeft(2,'0')}';
      }
    } catch (_) {}
    return null;
  }

  Future<void> _submit() async {
    for (final prop in _props) {
      if (!_isVisible(prop) || _isReadOnly(prop)) continue;
      final required = prop['isRequired'] as bool? ?? false;
      if (!required) continue;
      final id = prop['propId'] as int;
      final type = prop['propertytype'] as String? ?? '';
      final ctrl = _controllers[id];
      final val = _values[id];
      bool isEmpty;
      if (ctrl != null) {
        isEmpty = ctrl.text.trim().isEmpty;
      } else if (type == 'MFDatatypeLookup') {
        isEmpty = val == null;
      } else if (type == 'MFDatatypeMultiSelectLookup') {
        isEmpty = val == null || (val is List && val.isEmpty);
      } else {
        isEmpty = val == null || val.toString().trim().isEmpty;
      }
      if (isEmpty) {
        _showSnack('Required field "${prop['title']}" is missing', isError: true);
        return;
      }
    }

    final service = context.read<MFilesService>();
    final vaultGuid = service.selectedVault?.guid ?? '';
    setState(() => _submitting = true);

    try {
      final propsPayload = <Map<String, dynamic>>[];
      for (final prop in _props) {
        final id = prop['propId'] as int;
        final type = prop['propertytype'] as String? ?? '';
        (prop['value'] ?? '').toString();
        final isRequired = prop['isRequired'] as bool? ?? false;
        String resolvedValue;

        if (_isReadOnly(prop)) {
          continue;
        } else if (type == 'MFDatatypeText' || type == 'MFDatatypeMultiLineText' || type == 'MFDatatypeInteger') {
          resolvedValue = _controllers[id]?.text.trim() ?? '';
          if (resolvedValue.isEmpty && !isRequired) continue;
        } else if (type == 'MFDatatypeLookup') {
          final val = _values[id];
          if (val == null) { if (!isRequired) continue; resolvedValue = ''; }
          else resolvedValue = val.toString();
        } else if (type == 'MFDatatypeMultiSelectLookup') {
          final val = _values[id];
          if (val is List && val.isNotEmpty) resolvedValue = val.join(',');
          else { if (!isRequired) continue; resolvedValue = ''; }
        } else if (type == 'MFDatatypeDate') {
          resolvedValue = (_values[id] ?? '').toString();
          if (resolvedValue.isEmpty && !isRequired) continue;
        } else {
          resolvedValue = (_values[id] ?? _controllers[id]?.text ?? '').toString();
          if (resolvedValue.isEmpty && !isRequired) continue;
        }

        propsPayload.add({
          'propId': id, 'propertytype': type, 'value': resolvedValue,
          'isRequired': isRequired, 'isHidden': prop['isHidden'] ?? false,
          'isAutomatic': prop['isAutomatic'] ?? false, 'title': prop['title'] ?? '',
        });
      }

      final payload = {
        'VaultGuid': vaultGuid, 'ClassID': widget.classId,
        'ObjectId': widget.templateObjectId, 'UserID': service.currentUserId,
        'Properties': propsPayload,
      };

      await service.createObjectFromTemplate(payload);
      if (mounted) { _showSnack('Created successfully from template!'); Navigator.pop(context, true); }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(isError ? Icons.error_outline : Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 8), Expanded(child: Text(message)),
      ]),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: Duration(seconds: isError ? 4 : 2),
    ));
  }

  Future<void> _pickDate(int propId) async {
    final existing = _values[propId];
    DateTime initial;
    try {
      initial = existing != null && existing.toString().isNotEmpty
          ? _apiDateFmt.parse(existing.toString()) : DateTime.now();
    } catch (_) { initial = DateTime.now(); }
    final date = await showDatePicker(
      context: context, initialDate: initial,
      firstDate: DateTime(1900), lastDate: DateTime(2200),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(colorScheme: Theme.of(ctx).colorScheme.copyWith(primary: _primaryBlue)),
        child: child!,
      ),
    );
    if (date != null) setState(() => _values[propId] = _apiDateFmt.format(date));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.templateTitle, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          Text(widget.className, style: const TextStyle(fontSize: 12, color: Colors.white70)),
        ]),
      ),
      body: _loading ? const Center(child: CircularProgressIndicator())
          : _error != null ? _buildError() : _buildForm(),
    );
  }

  Widget _buildForm() {
    final editableProps = _props.where((p) => _isVisible(p) && !_isReadOnly(p)).toList();
    if (editableProps.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.info_outline, size: 40, color: Colors.grey.shade400), const SizedBox(height: 16),
        Text('No editable fields for this template.', style: TextStyle(fontSize: 15, color: Colors.grey.shade600), textAlign: TextAlign.center),
      ])));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _sectionHeader('Fill in Details', subtitle: 'These fields will be reflected in the document.'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7EAF0)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 14, offset: const Offset(0, 6))],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: List.generate(editableProps.length * 2 - 1, (i) {
              if (i.isOdd) return const Padding(padding: EdgeInsets.symmetric(vertical: 12), child: Divider(height: 1, thickness: 1, color: Color(0xFFE2E8F0)));
              return _buildEditableField(editableProps[i ~/ 2]);
            }),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation<Color>(Colors.white)))
                : const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(_submitting ? 'Creating...' : 'Create from Template', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              elevation: _submitting ? 0 : 2,
            ),
          ),
        ),
        const SizedBox(height: 20),
      ],
    );
  }

  Widget _buildEditableField(Map<String, dynamic> prop) {
    final id = prop['propId'] as int;
    final title = prop['title'] as String? ?? 'Field $id';
    final type = prop['propertytype'] as String? ?? '';
    final required = prop['isRequired'] as bool? ?? false;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: RichText(text: TextSpan(
          text: title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
          children: required ? const [TextSpan(text: ' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800))] : [],
        )),
      ),
      _buildInputForType(id, type, title, required),
    ]);
  }

  Widget _buildInputForType(int id, String type, String label, bool required) {
    switch (type) {
      case 'MFDatatypeText':
      case 'MFDatatypeMultiLineText':
        final ctrl = _controllers.putIfAbsent(id, () => TextEditingController());
        return TextField(
          controller: ctrl, maxLines: type == 'MFDatatypeMultiLineText' ? 4 : 1,
          onChanged: (_) => setState(() {}),
          decoration: _textDeco(hint: 'Enter ${label.toLowerCase()}...', filled: ctrl.text.trim().isNotEmpty),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
        );

      case 'MFDatatypeInteger':
        final ctrl = _controllers.putIfAbsent(id, () => TextEditingController());
        return TextField(
          controller: ctrl, keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: _textDeco(hint: 'Enter number...', filled: ctrl.text.trim().isNotEmpty),
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: Color(0xFF111827)),
        );

      case 'MFDatatypeDate':
        final val = _values[id];
        final has = val != null && val.toString().isNotEmpty;
        String display = 'Tap to select date';
        if (has) { try { display = _uiDateFmt.format(_apiDateFmt.parse(val.toString())); } catch (_) { display = val.toString(); } }
        return GestureDetector(
          onTap: () => _pickDate(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: has ? _filledFill : AppColors.surfaceLight, borderRadius: BorderRadius.circular(10),
              border: Border.all(color: has ? _filledBorder : Colors.grey.shade200, width: has ? 1.5 : 1),
            ),
            child: Row(children: [
              Container(padding: const EdgeInsets.all(5), decoration: BoxDecoration(color: has ? _primaryBlue.withOpacity(0.1) : Colors.grey.shade100, borderRadius: BorderRadius.circular(6)),
                child: Icon(Icons.calendar_today_rounded, size: 16, color: has ? _primaryBlue : AppColors.surfaceLight)),
              const SizedBox(width: 10),
              Expanded(child: Text(display, style: TextStyle(fontSize: 14, fontWeight: has ? FontWeight.w500 : FontWeight.w400, color: has ? const Color(0xFF111827) : AppColors.surfaceLight))),
              has ? const Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18) : Icon(Icons.keyboard_arrow_down, color: AppColors.surfaceLight, size: 20),
            ]),
          ),
        );

      case 'MFDatatypeLookup':
        final hasValue = _values[id] != null;
        return _lookupShell(
          label: label, required: required, hasValue: hasValue, isSingleSelect: true,
          field: LookupField(
            title: label, propertyId: id, isMultiSelect: false,
            preSelectedIds: hasValue ? [_values[id] as int] : [],
            onSelected: (items) => setState(() {
              if (items.isNotEmpty) { _values[id] = items.first.id; _selectedLookupItems[id] = items; }
              else { _values[id] = null; _selectedLookupItems.remove(id); }
            }),
          ),
        );

      case 'MFDatatypeMultiSelectLookup':
        final selectedItems = _selectedLookupItems[id] ?? [];
        final selectedIds = (_values[id] is List) ? (_values[id] as List).cast<int>() : <int>[];
        return _lookupShell(
          label: label, required: required, hasValue: selectedIds.isNotEmpty,
          selectedTexts: selectedItems.map((e) => e.displayValue.toString()).toList(),
          selectedItems: selectedItems, propertyId: id,
          field: LookupField(
            key: ValueKey(selectedIds.join(',')),
            title: label, propertyId: id, isMultiSelect: true, preSelectedIds: selectedIds,
            onSelected: (items) => setState(() {
              _values[id] = items.map((i) => i.id).toList();
              _selectedLookupItems[id] = items;
            }),
          ),
        );

      default:
        final ctrl = _controllers.putIfAbsent(id, () => TextEditingController());
        return TextField(
          controller: ctrl, onChanged: (_) => setState(() {}),
          decoration: _textDeco(hint: 'Enter value...', filled: ctrl.text.trim().isNotEmpty),
          style: const TextStyle(fontSize: 14, color: Color(0xFF111827)),
        );
    }
  }

  InputDecoration _textDeco({required String hint, required bool filled}) {
    return InputDecoration(
      hintText: hint, hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
      filled: true, fillColor: filled ? _filledFill : AppColors.surfaceLight, isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: filled ? _filledBorder : Colors.grey.shade200, width: filled ? 1.5 : 1)),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: _primaryBlue, width: 2)),
      suffixIcon: filled ? const Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18) : null,
    );
  }

  Widget _lookupShell({
    required String label, required bool required, required bool hasValue, required Widget field,
    bool isSingleSelect = false, List<String>? selectedTexts, List<dynamic>? selectedItems, int? propertyId,
  }) {
    final showMulti = selectedTexts != null && selectedTexts.isNotEmpty;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: hasValue ? _filledFill : AppColors.surfaceLight, borderRadius: BorderRadius.circular(10),
          border: Border.all(color: hasValue ? _filledBorder : Colors.grey.shade200, width: hasValue ? 1.5 : 1),
        ),
        child: Row(children: [
          Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: field)),
          if (hasValue) const Padding(padding: EdgeInsets.only(right: 12), child: Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18)),
        ]),
      ),
      if (showMulti) ...[
        const SizedBox(height: 10),
        Wrap(spacing: 6, runSpacing: 6, children: List.generate(selectedTexts.length, (index) {
          return Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(999), border: Border.all(color: const Color(0xFFBFDBFE))),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(selectedTexts[index], style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF1E40AF))),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  if (propertyId == null || selectedItems == null) return;
                  setState(() {
                    final newItems = List<dynamic>.from(selectedItems)..removeAt(index);
                    _selectedLookupItems[propertyId] = newItems;
                    _values[propertyId] = newItems.map((i) => i.id).toList();
                  });
                },
                child: Container(width: 16, height: 16, decoration: BoxDecoration(color: const Color(0xFF3B82F6).withOpacity(0.2), shape: BoxShape.circle), child: const Icon(Icons.close, size: 10, color: Color(0xFF1E40AF))),
              ),
            ]),
          );
        })),
      ],
      if (required && !hasValue) Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(children: [Icon(Icons.error_outline, size: 14, color: Colors.red.shade600), const SizedBox(width: 4), Text('This field is required', style: TextStyle(color: Colors.red.shade600, fontSize: 12))]),
      ),
    ]);
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: Color(0xFF0F172A))),
      if (subtitle != null) ...[const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF64748B)))],
    ]);
  }

  Widget _buildError() {
    return Center(child: Padding(padding: const EdgeInsets.all(32), child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400), const SizedBox(height: 16),
      const Text('Failed to load template', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)), const SizedBox(height: 8),
      Text(_error!, style: TextStyle(fontSize: 13, color: Colors.grey.shade600), textAlign: TextAlign.center), const SizedBox(height: 20),
      ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: _primaryBlue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
        onPressed: () { setState(() { _loading = true; _error = null; }); _loadProps(); },
        child: const Text('Retry'),
      ),
    ])));
  }
}