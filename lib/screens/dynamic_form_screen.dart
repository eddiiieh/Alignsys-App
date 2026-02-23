// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mfiles_app/widgets/lookup_field.dart';
import 'package:provider/provider.dart';

import '../models/class_property.dart';
import '../models/object_class.dart';
import '../models/object_creation_request.dart';
import '../models/vault_object_type.dart';
import '../services/mfiles_service.dart';

class DynamicFormScreen extends StatefulWidget {
  const DynamicFormScreen({
    super.key,
    required this.objectType,
    this.objectClass,
  });

  final VaultObjectType objectType;
  final ObjectClass? objectClass;

  @override
  State<DynamicFormScreen> createState() => _DynamicFormScreenState();
}

class _DynamicFormScreenState extends State<DynamicFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<int, dynamic> _formValues = {};
  final Map<int, List<dynamic>> _selectedLookupItems = {};

  File? _selectedFile;
  String? _selectedFileName;

  ObjectClass? _selectedClass;
  bool _isLoadingClasses = false;

  // Track which text fields have been filled
  final Map<int, bool> _fieldFilled = {};

  late VaultObjectType _currentObjectType;

  static final DateFormat _apiDateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _uiDateFmt = DateFormat('dd MMM yyyy');
  static final DateFormat _uiTimeFmt = DateFormat('HH:mm');

  static const _primaryBlue = Color(0xFF072F5F);
  static const _filledBorder = Color(0xFF2563EB);
  static const _filledFill = Color(0xFFF0F6FF);

  static const TextStyle _labelStyle = TextStyle(
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: Color(0xFF475569),
  );

  static const TextStyle _inputStyle = TextStyle(
    fontSize: 14.5,
    fontWeight: FontWeight.w500,
    color: Color(0xFF111827),
  );

  @override
  void initState() {
    super.initState();
    _currentObjectType = widget.objectType;
    _selectedClass = widget.objectClass;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = context.read<MFilesService>();

      setState(() => _isLoadingClasses = true);
      await service.fetchObjectClasses(widget.objectType.id);
      setState(() => _isLoadingClasses = false);

      if (_selectedClass != null) {
        await service.fetchClassProperties(widget.objectType.id, _selectedClass!.id);
      }
    });
  }

  @override
  void dispose() {
    super.dispose();
  }

  // ---------- UI helpers ----------
  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE7EAF0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F172A),
            letterSpacing: 0.2,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: Color(0xFF64748B),
            ),
          ),
        ],
      ],
    );
  }

  Widget _topLabel(String label, {required bool required}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: RichText(
        text: TextSpan(
          text: label,
          style: _labelStyle,
          children: required
              ? const [
                  TextSpan(
                    text: ' *',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }

  InputDecoration _decoBox({String? hint, String? helper, bool filled = false}) {
    return InputDecoration(
      hintText: hint,
      helperText: helper,
      helperStyle: const TextStyle(fontSize: 12),
      isDense: true,
      filled: true,
      fillColor: filled ? _filledFill : Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: filled
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
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
      suffixIcon: filled
          ? const Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18)
          : null,
    );
  }

  Widget _requiredHint(bool show) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 14, color: Colors.red.shade600),
          const SizedBox(width: 4),
          Text(
            'This field is required',
            style: TextStyle(color: Colors.red.shade600, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _fieldShell({
    required String label,
    required bool required,
    required Widget field,
    bool showRequiredHint = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topLabel(label, required: required),
        field,
        _requiredHint(showRequiredHint),
      ],
    );
  }

  // Updated lookup shell — no pill for single select, pills with × for multi select
  Widget _lookupShell({
    required String label,
    required bool required,
    required bool hasValue,
    required Widget field,
    bool isSingleSelect = false,
    List<String>? selectedTexts,
    List<dynamic>? selectedItems,
    int? propertyId,
  }) {
    final showMulti = (selectedTexts != null && selectedTexts.isNotEmpty);
    final isFilled = hasValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topLabel(label, required: required),

        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            color: isFilled ? _filledFill : Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isFilled ? _filledBorder : Colors.grey.shade200,
              width: isFilled ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: field,
                ),
              ),
              if (isFilled)
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18),
                ),
            ],
          ),
        ),

        // Multi-select pills with × remove
        if (showMulti) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(selectedTexts!.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        selectedTexts[index],
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFF1E40AF),
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () {
                          if (propertyId == null || selectedItems == null) return;
                          setState(() {
                            final newItems = List<dynamic>.from(selectedItems)..removeAt(index);
                            _selectedLookupItems[propertyId] = newItems;
                            _formValues[propertyId] = newItems.map((i) => i.id).toList();
                          });
                        },
                        child: Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFF3B82F6).withOpacity(0.2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 10, color: Color(0xFF1E40AF)),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ],

        _requiredHint(required && !hasValue),
      ],
    );
  }

  // ---------- Object type switcher ----------
  Future<void> _onObjectTypeChanged(VaultObjectType newType) async {
    setState(() {
      _currentObjectType = newType;
      _selectedClass = null;
      _formValues.clear();
      _selectedLookupItems.clear();
      _fieldFilled.clear();
      _selectedFile = null;
      _selectedFileName = null;
      _isLoadingClasses = true;
    });

    final service = context.read<MFilesService>();
    await service.fetchObjectClasses(newType.id);
    setState(() => _isLoadingClasses = false);
  }

  // ---------- Actions ----------
  Future<void> _onClassSelected(ObjectClass? objectClass) async {
    if (objectClass == null) return;

    setState(() {
      _selectedClass = objectClass;
      _formValues.clear();
      _selectedLookupItems.clear();
      _fieldFilled.clear();
      _selectedFile = null;
      _selectedFileName = null;
    });

    await context.read<MFilesService>().fetchClassProperties(_currentObjectType.id, objectClass.id);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    setState(() {
      _selectedFile = File(result.files.single.path!);
      _selectedFileName = result.files.single.name;
    });
  }

  DateTime _safeParseDateOnly(String yyyyMmDd) => DateTime.parse('${yyyyMmDd}T00:00:00');

  Future<void> _pickDate(ClassProperty property) async {
    final existing = _formValues[property.id];
    final initialDate = (existing is String && existing.isNotEmpty)
        ? _safeParseDateOnly(existing)
        : DateTime.now();

    final date = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(1800),
      lastDate: DateTime(2200),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _primaryBlue),
        ),
        child: child!,
      ),
    );

    if (date != null) {
      setState(() => _formValues[property.id] = _apiDateFmt.format(date));
    }
  }

  Future<void> _pickTime(ClassProperty property) async {
    final existing = _formValues[property.id];
    final initialTime = (existing is String && existing.isNotEmpty)
        ? TimeOfDay.fromDateTime(DateTime.tryParse(existing) ?? DateTime.now())
        : TimeOfDay.now();

    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _primaryBlue),
        ),
        child: child!,
      ),
    );

    if (time != null) {
      final now = DateTime.now();
      final combined = DateTime(now.year, now.month, now.day, time.hour, time.minute);
      setState(() => _formValues[property.id] = combined.toIso8601String());
    }
  }

  String _formatDateForUi(String yyyyMmDd) {
    try {
      return _uiDateFmt.format(_safeParseDateOnly(yyyyMmDd));
    } catch (_) {
      return 'Invalid date';
    }
  }

  String _formatTimeForUi(String isoString) {
    try {
      final dt = DateTime.parse(isoString);
      return _uiTimeFmt.format(dt);
    } catch (_) {
      return 'Invalid time';
    }
  }

  // ---------- Searchable dropdown dialog ----------
  Future<T?> _showSearchableDropdown<T>({
    required String title,
    required List<T> items,
    required String Function(T) labelOf,
    T? selected,
  }) async {
    final controller = TextEditingController();
    List<T> filtered = List.from(items);

    return showDialog<T>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setInner) {
            return Dialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.75,
                ),
                child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                    decoration: const BoxDecoration(
                      color: _primaryBlue,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(ctx),
                        ),
                      ],
                    ),
                  ),
                  // Search field
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: controller,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
                        prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: _primaryBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        isDense: true,
                        suffixIcon: controller.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close, size: 16, color: Colors.grey.shade400),
                                onPressed: () {
                                  controller.clear();
                                  setInner(() => filtered = List.from(items));
                                },
                              )
                            : null,
                      ),
                      onChanged: (q) {
                        setInner(() {
                          filtered = items
                              .where((i) => labelOf(i).toLowerCase().contains(q.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                  ),
                  // Count
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                    child: Row(
                      children: [
                        Text(
                          '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                  // List — Flexible so it never overflows the dialog
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off, size: 36, color: Colors.grey.shade300),
                                const SizedBox(height: 8),
                                Text(
                                  'No matches found',
                                  style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade100),
                            itemBuilder: (_, index) {
                              final item = filtered[index];
                              final label = labelOf(item);
                              final isSelected = selected != null && labelOf(selected) == label;
                              return Material(
                                color: isSelected
                                    ? const Color(0xFFEFF6FF)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () => Navigator.pop(ctx, item),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            label,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: isSelected
                                                  ? FontWeight.w600
                                                  : FontWeight.w500,
                                              color: isSelected
                                                  ? const Color(0xFF1E40AF)
                                                  : const Color(0xFF1A1A1A),
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          const Icon(Icons.check_rounded,
                                              size: 18, color: Color(0xFF2563EB)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
              ), // ConstrainedBox
            );
          },
        );
      },
    );
  }

  // ---------- Field builders ----------
  Widget _dateField(ClassProperty p) {
    final v = _formValues[p.id];
    final has = v is String && v.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topLabel(p.title, required: p.isRequired),
        InkWell(
          onTap: () => _pickDate(p),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: has ? _filledFill : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: has ? _filledBorder : Colors.grey.shade200,
                width: has ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: has ? _primaryBlue.withOpacity(0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: has ? _primaryBlue : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    has ? _formatDateForUi(v) : 'Tap to select date',
                    style: _inputStyle.copyWith(
                      color: has ? const Color(0xFF111827) : Colors.grey.shade600,
                      fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (has)
                  const Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18)
                else
                  Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600, size: 20),
              ],
            ),
          ),
        ),
        _requiredHint(p.isRequired && !has),
      ],
    );
  }

  Widget _timeField(ClassProperty p) {
    final v = _formValues[p.id];
    final has = v is String && v.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topLabel(p.title, required: p.isRequired),
        InkWell(
          onTap: () => _pickTime(p),
          borderRadius: BorderRadius.circular(12),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: has ? _filledFill : Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: has ? _filledBorder : Colors.grey.shade200,
                width: has ? 1.5 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: has ? _primaryBlue.withOpacity(0.1) : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color: has ? _primaryBlue : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    has ? _formatTimeForUi(v) : 'Tap to select time',
                    style: _inputStyle.copyWith(
                      color: has ? const Color(0xFF111827) : Colors.grey.shade600,
                      fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
                if (has)
                  const Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18)
                else
                  Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600, size: 20),
              ],
            ),
          ),
        ),
        _requiredHint(p.isRequired && !has),
      ],
    );
  }

  Widget _buildField(ClassProperty property) {
    switch (property.propertyType) {
      case 'MFDatatypeLookup': {
        final hasValue = _formValues[property.id] != null;
        final selectedItems = _selectedLookupItems[property.id] ?? [];
        final selectedText = selectedItems.isNotEmpty ? selectedItems.first.displayValue : '';

        return _lookupShell(
          label: property.title,
          required: property.isRequired,
          hasValue: hasValue,
          isSingleSelect: true,
          field: LookupField(
            title: property.title,
            propertyId: property.id,
            isMultiSelect: false,
            preSelectedIds: _formValues[property.id] == null
                ? const []
                : [(_formValues[property.id] as int)],
            onSelected: (items) {
              setState(() {
                if (items.isNotEmpty) {
                  _formValues[property.id] = items.first.id;
                  _selectedLookupItems[property.id] = items;
                } else {
                  _formValues[property.id] = null;
                  _selectedLookupItems.remove(property.id);
                }
              });
            },
          ),
        );
      }

      case 'MFDatatypeMultiSelectLookup': {
        final selectedItems = _selectedLookupItems[property.id] ?? [];
        final selectedIds = (_formValues[property.id] is List)
            ? (_formValues[property.id] as List).cast<int>()
            : <int>[];

        final selectedTexts = selectedItems.map((e) => e.displayValue.toString()).toList();

        return _lookupShell(
          label: property.title,
          required: property.isRequired,
          hasValue: selectedIds.isNotEmpty,
          selectedTexts: selectedTexts,
          selectedItems: selectedItems,
          propertyId: property.id,
          field: LookupField(
            // Key changes whenever the selection changes, so LookupField's
            // didUpdateWidget fires and re-syncs its internal state.
            key: ValueKey(
              ((_formValues[property.id] is List)
                      ? (_formValues[property.id] as List).cast<int>()
                      : <int>[])
                  .join(','),
            ),
            title: property.title,
            propertyId: property.id,
            isMultiSelect: true,
            preSelectedIds: (_formValues[property.id] is List)
                ? (_formValues[property.id] as List).cast<int>()
                : const [],
            onSelected: (items) {
              setState(() {
                _formValues[property.id] = items.map((i) => i.id).toList();
                _selectedLookupItems[property.id] = items;
              });
            },
          ),
        );
      }

      case 'MFDatatypeText': {
        final isFilled = _fieldFilled[property.id] == true;
        return _fieldShell(
          label: property.title,
          required: property.isRequired,
          field: TextFormField(
            decoration: _decoBox(
              hint: 'Enter ${property.title.toLowerCase()}',
              filled: isFilled,
            ),
            style: _inputStyle,
            validator: (value) {
              if (property.isRequired && (value == null || value.trim().isEmpty)) {
                return 'This field is required';
              }
              return null;
            },
            onChanged: (value) {
              setState(() {
                _formValues[property.id] = value;
                _fieldFilled[property.id] = value.trim().isNotEmpty;
              });
            },
          ),
        );
      }

      case 'MFDatatypeMultiLineText': {
        final isFilled = _fieldFilled[property.id] == true;
        return _fieldShell(
          label: property.title,
          required: property.isRequired,
          field: TextFormField(
            decoration: _decoBox(
              hint: 'Enter ${property.title.toLowerCase()}',
              filled: isFilled,
            ),
            style: _inputStyle,
            maxLines: 4,
            validator: (value) {
              if (property.isRequired && (value == null || value.trim().isEmpty)) {
                return 'This field is required';
              }
              return null;
            },
            onChanged: (value) {
              setState(() {
                _formValues[property.id] = value;
                _fieldFilled[property.id] = value.trim().isNotEmpty;
              });
            },
          ),
        );
      }

      case 'MFDatatypeInteger': {
        final isFilled = _fieldFilled[property.id] == true;
        return _fieldShell(
          label: property.title,
          required: property.isRequired,
          field: TextFormField(
            decoration: _decoBox(
              hint: 'Enter ${property.title.toLowerCase()}',
              filled: isFilled,
            ),
            style: _inputStyle,
            keyboardType: TextInputType.number,
            validator: (value) {
              if (property.isRequired && (value == null || value.trim().isEmpty)) {
                return 'This field is required';
              }
              if (value != null && value.trim().isNotEmpty && int.tryParse(value) == null) {
                return 'Enter a valid number';
              }
              return null;
            },
            onChanged: (value) {
              setState(() {
                _formValues[property.id] = int.tryParse(value);
                _fieldFilled[property.id] = value.trim().isNotEmpty;
              });
            },
          ),
        );
      }

      case 'MFDatatypeDate':
        return _dateField(property);

      case 'MFDatatypeTime':
        return _timeField(property);

      case 'MFDatatypeBoolean': {
        final current = _formValues[property.id];
        final bool? currentBool = current is bool ? current : null;
        final isFilled = currentBool != null;

        return _fieldShell(
          label: property.title,
          required: property.isRequired,
          field: GestureDetector(
            onTap: () async {
              final result = await _showSearchableDropdown<bool>(
                title: property.title,
                items: const [true, false],
                labelOf: (v) => v ? 'Yes' : 'No',
                selected: currentBool,
              );
              if (result != null) {
                setState(() => _formValues[property.id] = result);
              }
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: isFilled ? _filledFill : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isFilled ? _filledBorder : Colors.grey.shade200,
                  width: isFilled ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      currentBool == null
                          ? 'Select ${property.title.toLowerCase()}'
                          : (currentBool ? 'Yes' : 'No'),
                      style: _inputStyle.copyWith(
                        color: currentBool == null
                            ? Colors.grey.shade500
                            : const Color(0xFF111827),
                        fontWeight: currentBool == null ? FontWeight.w400 : FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isFilled)
                    const Icon(Icons.check_circle_rounded, color: _filledBorder, size: 18)
                  else
                    Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600, size: 20),
                ],
              ),
            ),
          ),
        );
      }

      default: {
        final isFilled = _fieldFilled[property.id] == true;
        return _fieldShell(
          label: property.title,
          required: property.isRequired,
          field: TextFormField(
            decoration: _decoBox(
              hint: 'Enter ${property.title.toLowerCase()}',
              filled: isFilled,
            ),
            style: _inputStyle,
            validator: (value) {
              if (property.isRequired && (value == null || value.trim().isEmpty)) {
                return 'This field is required';
              }
              return null;
            },
            onChanged: (value) {
              setState(() {
                _formValues[property.id] = value;
                _fieldFilled[property.id] = value.trim().isNotEmpty;
              });
            },
          ),
        );
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              isError ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

  Future<void> _submitForm() async {
    if (_selectedClass == null) {
      _showSnackBar('Please select a class first', isError: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final service = context.read<MFilesService>();

    for (final prop in service.classProperties.where((p) => !p.isHidden && !p.isAutomatic)) {
      if (!prop.isRequired) continue;
      final v = _formValues[prop.id];

      if (prop.propertyType == 'MFDatatypeLookup' && v == null) {
        _showSnackBar('Required field "${prop.title}" is missing', isError: true);
        return;
      }
      if (prop.propertyType == 'MFDatatypeMultiSelectLookup' &&
          (v == null || (v is List && v.isEmpty))) {
        _showSnackBar('Required field "${prop.title}" is missing', isError: true);
        return;
      }
      if (prop.propertyType == 'MFDatatypeDate' && !(v is String && v.isNotEmpty)) {
        _showSnackBar('Required field "${prop.title}" is missing', isError: true);
        return;
      }
      if (prop.propertyType == 'MFDatatypeTime' && !(v is String && v.isNotEmpty)) {
        _showSnackBar('Required field "${prop.title}" is missing', isError: true);
        return;
      }
    }

    String? uploadId;
    if (_currentObjectType.isDocument) {
      if (_selectedFile == null) {
        _showSnackBar('Please select a file for document objects', isError: true);
        return;
      }
      uploadId = await service.uploadFile(_selectedFile!);
      if (uploadId == null) {
        _showSnackBar('File upload failed', isError: true);
        return;
      }
    }

    final properties = <PropertyValueRequest>[];

    final hasClassProperty = service.classProperties.any((p) => p.id == 100);
    if (hasClassProperty) {
      properties.add(
        PropertyValueRequest(
          propId: 100,
          value: _selectedClass!.id.toString(),
          propertyType: 'MFDatatypeLookup',
        ),
      );
    }

    for (final prop in service.classProperties) {
      if (prop.isAutomatic) continue;
      if (prop.id == 100 && hasClassProperty) continue;

      final value = _formValues[prop.id];
      if (value == null && !prop.isRequired) continue;

      if (value == null && prop.isRequired) {
        _showSnackBar('Required field "${prop.title}" is missing', isError: true);
        return;
      }

      properties.add(
        PropertyValueRequest(
          propId: prop.id,
          value: value,
          propertyType: prop.propertyType,
        ),
      );
    }

    final classHasTitleProp = service.classProperties.any((p) => p.id == 0);
    final hasTitleInPayload = properties.any((p) => p.propId == 0);

    if (classHasTitleProp && !hasTitleInPayload) {
      final title = (_formValues[0] ?? '').toString().trim();
      if (title.isEmpty) {
        _showSnackBar('Name or title is required', isError: true);
        return;
      }
      properties.add(PropertyValueRequest(propId: 0, value: title, propertyType: 'MFDatatypeText'));
    }

    final request = ObjectCreationRequest(
      objectID: _currentObjectType.id,
      objectTypeID: _currentObjectType.id,
      classID: _selectedClass!.id,
      properties: properties,
      vaultGuid: service.vaultGuidWithBraces,
      userID: service.currentUserId,
      uploadId: uploadId,
    );

    final success = await service.createObject(request);

    if (!mounted) return;

    if (success) {
      _showSnackBar('Object created successfully!');
      Navigator.pop(context);
    } else {
      _showSnackBar('Failed to create object: ${service.error}', isError: true);
    }
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A1541),
          elevation: 0,
          toolbarHeight: 64,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Padding(
            padding: const EdgeInsets.only(left: 12.0, right: 8.0),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/alignsysnew.png',
                  height: 55,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        body: Consumer<MFilesService>(
          builder: (context, service, _) {
            final objectClasses = service.objectClasses
                .where((cls) => cls.objectTypeId == _currentObjectType.id)
                .toList();

            final visibleProperties = service.classProperties
                .where((p) => !p.isHidden && !p.isAutomatic)
                .toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // ── Header card with object type switcher ──
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Object Type',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF94A3B8),
                                    letterSpacing: 0.8,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                GestureDetector(
                                  onTap: () async {
                                    final result = await _showSearchableDropdown<VaultObjectType>(
                                      title: 'Select Object Type',
                                      items: service.objectTypes,
                                      labelOf: (t) => t.displayName,
                                      selected: _currentObjectType,
                                    );
                                    if (result != null && result.id != _currentObjectType.id) {
                                      await _onObjectTypeChanged(result);
                                    }
                                  },
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Create ${_currentObjectType.displayName}',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w800,
                                          color: Color(0xFF0F172A),
                                          letterSpacing: 0.2,
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: _primaryBlue.withOpacity(0.1),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              'Change',
                                              style: TextStyle(
                                                fontSize: 10,
                                                fontWeight: FontWeight.w700,
                                                color: _primaryBlue,
                                              ),
                                            ),
                                            SizedBox(width: 2),
                                            Icon(Icons.swap_horiz_rounded,
                                                size: 12, color: _primaryBlue),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _selectedClass != null
                            ? 'Class: ${_selectedClass!.displayName}'
                            : 'Select a class to continue',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                          color: Color(0xFF64748B),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── Class selector ──
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('Select class',
                          subtitle: 'Choose the category for this object.'),
                      const SizedBox(height: 14),
                      if (_isLoadingClasses)
                        Column(
                          children: [
                            const LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Color(0xFFE8EEF5),
                              valueColor: AlwaysStoppedAnimation<Color>(_primaryBlue),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Loading classes...',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        )
                      else
                        _fieldShell(
                          label: 'Class',
                          required: false,
                          field: GestureDetector(
                            onTap: () async {
                              final result =
                                  await _showSearchableDropdown<ObjectClass>(
                                title: 'Select Class',
                                items: objectClasses,
                                labelOf: (c) => c.displayName,
                                selected: _selectedClass,
                              );
                              if (result != null) _onClassSelected(result);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 14),
                              decoration: BoxDecoration(
                                color: _selectedClass != null
                                    ? _filledFill
                                    : Colors.grey.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedClass != null
                                      ? _filledBorder
                                      : Colors.grey.shade200,
                                  width: _selectedClass != null ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      _selectedClass?.displayName ??
                                          'Tap to select class',
                                      style: _inputStyle.copyWith(
                                        color: _selectedClass != null
                                            ? const Color(0xFF111827)
                                            : Colors.grey.shade500,
                                        fontWeight: _selectedClass != null
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                  ),
                                  if (_selectedClass != null)
                                    const Icon(Icons.check_circle_rounded,
                                        color: _filledBorder, size: 18)
                                  else
                                    Icon(Icons.keyboard_arrow_down,
                                        color: Colors.grey.shade600, size: 20),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // ── File upload ──
                if (_selectedClass != null && _currentObjectType.isDocument) ...[
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('File upload',
                            subtitle: 'Attach the document file.'),
                        const SizedBox(height: 14),
                        _topLabel('File', required: true),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: _selectedFile != null
                                ? _filledFill
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedFile != null
                                  ? _filledBorder
                                  : Colors.grey.shade200,
                              width: _selectedFile != null ? 1.5 : 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedFile != null
                                    ? Icons.insert_drive_file_rounded
                                    : Icons.cloud_upload_outlined,
                                color: _selectedFile != null
                                    ? _primaryBlue
                                    : Colors.grey.shade400,
                                size: 22,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _selectedFileName ?? 'No file selected',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: _inputStyle.copyWith(
                                        color: _selectedFile != null
                                            ? const Color(0xFF111827)
                                            : Colors.grey.shade600,
                                        fontWeight: _selectedFile != null
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                      ),
                                    ),
                                    if (_selectedFile != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Ready to upload',
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade600),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _pickFile,
                                icon: const Icon(Icons.folder_open_rounded,
                                    size: 16),
                                label: const Text('Browse'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _primaryBlue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 16, vertical: 12),
                                  shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10)),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                        _requiredHint(_selectedFile == null),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // ── Properties ──
                if (_selectedClass != null) ...[
                  _card(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader('Properties',
                              subtitle: 'Fill in the required details below.'),
                          const SizedBox(height: 14),
                          if (service.isLoading && service.classProperties.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Column(
                                  children: [
                                    const CircularProgressIndicator(),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Loading properties...',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (visibleProperties.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 24),
                              child: Center(
                                child: Column(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(16),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.shade100,
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(Icons.info_outline,
                                          size: 32,
                                          color: Colors.grey.shade400),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No properties to configure',
                                      style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            // Fields with thin dividers between them
                            Column(
                              children: List.generate(
                                visibleProperties.length * 2 - 1,
                                (index) {
                                  if (index.isOdd) {
                                    return Padding(
                                      padding: const EdgeInsets.symmetric(vertical: 12),
                                      child: Divider(
                                        height: 1,
                                        thickness: 1,
                                        color: Colors.grey.shade100,
                                      ),
                                    );
                                  }
                                  final p = visibleProperties[index ~/ 2];
                                  return _buildField(p);
                                },
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: service.isLoading ? null : _submitForm,
                      icon: service.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.check_circle_rounded, size: 20),
                      label: Text(
                        service.isLoading ? 'Creating...' : 'Create Object',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.3,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        elevation: service.isLoading ? 0 : 2,
                        shadowColor: _primaryBlue.withOpacity(0.3),
                        disabledBackgroundColor: Colors.grey.shade300,
                        disabledForegroundColor: Colors.grey.shade600,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 20),
              ],
            );
          },
        ),
      ),
    );
  }
}