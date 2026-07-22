// ignore_for_file: deprecated_member_use
import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../widgets/auto_suggest_dialog.dart';
import '../widgets/lookup_field.dart';
import 'package:provider/provider.dart';

import '../models/class_property.dart';
import '../models/object_class.dart';
import '../models/object_creation_request.dart';
import '../models/vault_object_type.dart';

import '../widgets/network_banner.dart';
import '../services/mfiles_service.dart';
import '../theme/app_colors.dart';
import '../models/lookup_item.dart';
import '../models/quick_create_result.dart';

class DynamicFormScreen extends StatefulWidget {
  const DynamicFormScreen({
    super.key,
    required this.objectType,
    this.objectClass,
    this.isQuickCreate = false,
    this.scannedFile,
  });

  final VaultObjectType objectType;
  final ObjectClass? objectClass;
  /// When set, pre-populates the file attachment section with a scanned PDF
  /// so the user only needs to pick a class and fill metadata.
  final File? scannedFile;

  /// True when pushed from the "+" button next to a lookup field on
  /// another form, to create a related object inline. Locks the
  /// object-type switcher (the type is dictated by the calling lookup) and,
  /// on success, pops a [QuickCreateResult] instead of popping empty.
  final bool isQuickCreate;

  @override
  State<DynamicFormScreen> createState() => _DynamicFormScreenState();
}

class _DynamicFormScreenState extends State<DynamicFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<int, dynamic> _formValues = {};
  final Map<int, List<dynamic>> _selectedLookupItems = {};

  PlatformFile? _selectedFile;
  String? _selectedFileName;

  ObjectClass? _selectedClass;
  bool _isLoadingClasses = false;

  // ── FIX: local snapshot of properties for the currently selected class.
  //         This prevents the service's shared `classProperties` list (which
  //         holds whatever was fetched last) from leaking into this form when
  //         the user switches class quickly or two fetches race each other.
  List<ClassProperty> _localProperties = [];

  // Track which text fields have been filled
  final Map<int, bool> _fieldFilled = {};

  late VaultObjectType _currentObjectType;

  static final DateFormat _apiDateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _uiDateFmt = DateFormat('dd MMM yyyy');
  static final DateFormat _uiTimeFmt = DateFormat('HH:mm');

  static const _primaryBlue = AppColors.primary;
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

    // Pre-populate file section when launched from the scan flow.
    if (widget.scannedFile != null) {
      _selectedFile = PlatformFile(
        name: widget.scannedFile!.path.split('/').last,
        path: widget.scannedFile!.path,
        size: widget.scannedFile!.lengthSync(),
      );
      _selectedFileName = _selectedFile!.name;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = context.read<MFilesService>();

      setState(() => _isLoadingClasses = true);
      await service.fetchObjectClasses(widget.objectType.id);
      setState(() => _isLoadingClasses = false);

      // ── FIX: if a class was pre-selected (passed via widget.objectClass),
      //         snapshot its properties into _localProperties after fetching.
      if (_selectedClass != null) {
        final targetClassId = _selectedClass!.id;
        await service.fetchClassProperties(
            widget.objectType.id, _selectedClass!.id);
        if (mounted && _selectedClass?.id == targetClassId) {
          setState(() {
            _localProperties = List.from(service.classProperties);
          });
        }
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
                    style: TextStyle(
                        color: Colors.red, fontWeight: FontWeight.w800),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }

  InputDecoration _decoBox(
      {String? hint, String? helper, bool filled = false}) {
    return InputDecoration(
      hintText: hint,
      helperText: helper,
      helperStyle: const TextStyle(fontSize: 12),
      isDense: true,
      filled: true,
      fillColor: filled ? _filledFill : AppColors.surfaceLight,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
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
          ? const Icon(Icons.check_circle_rounded,
              color: _filledBorder, size: 18)
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

  Widget _lookupShell({
    required String label,
    required bool required,
    required bool hasValue,
    required Widget field,
    bool isSingleSelect = false,
    List<String>? selectedTexts,
    List<dynamic>? selectedItems,
    int? propertyId,
    VoidCallback? onCreateNew,
  }) {
    final showMulti = (selectedTexts != null && selectedTexts.isNotEmpty);
    final isFilled = hasValue;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _topLabel(label, required: required),

        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  color: isFilled ? _filledFill : AppColors.surfaceLight,
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
                        child: Icon(Icons.check_circle_rounded,
                            color: _filledBorder, size: 18),
                      ),
                  ],
                ),
              ),
            ),
            if (onCreateNew != null) ...[
              const SizedBox(width: 8),
              _quickCreateButton(onCreateNew),
            ],
          ],
        ),

        if (showMulti) ...[
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(selectedTexts.length, (index) {
              return AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEFF6FF),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFFBFDBFE)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          selectedTexts[index],
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
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
                          if (propertyId == null || selectedItems == null)
                            return;
                          setState(() {
                            final newItems =
                                List<dynamic>.from(selectedItems)
                                  ..removeAt(index);
                            _selectedLookupItems[propertyId] = newItems;
                            _formValues[propertyId] =
                                newItems.map((i) => i.id).toList();
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
                ),
              );
            }),
          ),
        ],

        _requiredHint(required && !hasValue),
      ],
    );
  }

  /// The blue "+" button rendered next to lookup fields, matching the web
  /// app's inline quick-create affordance.
  Widget _quickCreateButton(VoidCallback onTap) {
    return Material(
      color: _primaryBlue,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.add, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  // ---------- Object type switcher ----------
  Future<void> _onObjectTypeChanged(VaultObjectType newType) async {
    setState(() {
      _currentObjectType = newType;
      _selectedClass = null;
      _localProperties = []; // ── FIX: clear local snapshot
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

  /// Called when the user picks a class from the dropdown.
  ///
  /// Key fix: we capture [targetClassId] before the async gap so we can
  /// check on return whether the user has already switched to a different
  /// class while the fetch was in flight.  If they have, we discard the
  /// stale result instead of overwriting _localProperties with the wrong data.
  Future<void> _onClassSelected(ObjectClass? objectClass) async {
    if (objectClass == null) return;

    // Capture the class we are fetching for.
    final targetClassId = objectClass.id;

    setState(() {
      _selectedClass = objectClass;
      _formValues.clear();
      _selectedLookupItems.clear();
      _fieldFilled.clear();
      if (widget.scannedFile == null) {
        _selectedFile = null;
        _selectedFileName = null;
      }
      // ── FIX: clear immediately so the UI never shows stale properties
      //         from the previously selected class while the fetch runs.
      _localProperties = [];
    });

    final service = context.read<MFilesService>();
    await service.fetchClassProperties(_currentObjectType.id, objectClass.id);

    // ── FIX: only update _localProperties if the user is still on the same
    //         class. If they tapped another class while we were waiting, the
    //         second _onClassSelected call will update things instead.
    if (!mounted) return;
    if (_selectedClass?.id != targetClassId) return;

    setState(() {
      _localProperties = List.from(service.classProperties);
    });
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
    );

    if (result != null && result.files.isNotEmpty) {
      final file = result.files.first;

      setState(() {
        _selectedFile = file;
        _selectedFileName = file.name;
      });
    }
  }

  DateTime _safeParseDateOnly(String yyyyMmDd) =>
      DateTime.parse('${yyyyMmDd}T00:00:00');

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
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: _primaryBlue),
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
        ? TimeOfDay.fromDateTime(
            DateTime.tryParse(existing) ?? DateTime.now())
        : TimeOfDay.now();

    final time = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context)
              .colorScheme
              .copyWith(primary: _primaryBlue),
        ),
        child: child!,
      ),
    );

    if (time != null) {
      final now = DateTime.now();
      final combined = DateTime(
          now.year, now.month, now.day, time.hour, time.minute);
      setState(
          () => _formValues[property.id] = combined.toIso8601String());
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
    final focusNode = FocusNode();
    List<T> filtered = List.from(items);

    final result = await showDialog<T>(
      context: context,
      builder: (ctx) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          focusNode.requestFocus();
        });

        return StatefulBuilder(
          builder: (ctx, setInner) {
            return Dialog(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(
                  horizontal: 20, vertical: 40),
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight:
                      MediaQuery.of(context).size.height * 0.75,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Container(
                      padding:
                          const EdgeInsets.fromLTRB(20, 20, 12, 16),
                      decoration: const BoxDecoration(
                        color: _primaryBlue,
                        borderRadius: BorderRadius.vertical(
                            top: Radius.circular(20)),
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
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 20),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                    ),
                    // Search field
                    Padding(
                      padding:
                          const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        autofocus: true,
                        decoration: InputDecoration(
                          hintText: 'Search...',
                          hintStyle: TextStyle(
                              color: Colors.grey.shade400,
                              fontSize: 14),
                          prefixIcon: Icon(Icons.search,
                              color: Colors.grey.shade400, size: 20),
                          filled: true,
                          fillColor: AppColors.surfaceLight,
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
                                color: _primaryBlue, width: 2),
                          ),
                          contentPadding:
                              const EdgeInsets.symmetric(
                                  horizontal: 14, vertical: 12),
                          isDense: true,
                          suffixIcon: controller.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(Icons.close,
                                      size: 16,
                                      color: Colors.grey.shade400),
                                  onPressed: () {
                                    controller.clear();
                                    setInner(() =>
                                        filtered = List.from(items));
                                  },
                                )
                              : null,
                        ),
                        onChanged: (q) {
                          setInner(() {
                            filtered = items
                                .where((i) => labelOf(i)
                                    .toLowerCase()
                                    .contains(q.toLowerCase()))
                                .toList();
                          });
                        },
                      ),
                    ),
                    // Count
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 4),
                      child: Row(
                        children: [
                          Text(
                            '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                    ),
                    // List
                    Flexible(
                      child: filtered.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.search_off,
                                      size: 36,
                                      color: Colors.grey.shade300),
                                  const SizedBox(height: 8),
                                  Text(
                                    'No matches found',
                                    style: TextStyle(
                                        color:
                                            AppColors.surfaceLight,
                                        fontSize: 13),
                                  ),
                                ],
                              ),
                            )
                          : ListView.separated(
                              shrinkWrap: true,
                              padding: const EdgeInsets.symmetric(
                                  vertical: 8),
                              itemCount: filtered.length,
                              separatorBuilder: (_, __) => Divider(
                                  height: 1,
                                  color: Colors.grey.shade100),
                              itemBuilder: (_, index) {
                                final item = filtered[index];
                                final label = labelOf(item);
                                final isSelected = selected != null &&
                                    labelOf(selected) == label;
                                return Material(
                                  color: isSelected
                                      ? const Color(0xFFEFF6FF)
                                      : Colors.transparent,
                                  child: InkWell(
                                    onTap: () =>
                                        Navigator.pop(ctx, item),
                                    child: Padding(
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 20,
                                              vertical: 14),
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
                                                    ? const Color(
                                                        0xFF1E40AF)
                                                    : const Color(
                                                        0xFF1A1A1A),
                                              ),
                                            ),
                                          ),
                                          if (isSelected)
                                            const Icon(
                                                Icons.check_rounded,
                                                size: 18,
                                                color: Color(
                                                    0xFF2563EB)),
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
              ),
            );
          },
        );
      },
    );

    return result;
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
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: has ? _filledFill : AppColors.surfaceLight,
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
                    color: has
                        ? _primaryBlue.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color:
                        has ? _primaryBlue : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    has ? _formatDateForUi(v) : 'Tap to select date',
                    style: _inputStyle.copyWith(
                      color: has
                          ? const Color(0xFF111827)
                          : AppColors.surfaceLight,
                      fontWeight: has
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (has)
                  const Icon(Icons.check_circle_rounded,
                      color: _filledBorder, size: 18)
                else
                  Icon(Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600, size: 20),
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
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: has ? _filledFill : AppColors.surfaceLight,
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
                    color: has
                        ? _primaryBlue.withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color:
                        has ? _primaryBlue : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    has ? _formatTimeForUi(v) : 'Tap to select time',
                    style: _inputStyle.copyWith(
                      color: has
                          ? const Color(0xFF111827)
                          : AppColors.surfaceLight,
                      fontWeight: has
                          ? FontWeight.w500
                          : FontWeight.w400,
                    ),
                  ),
                ),
                if (has)
                  const Icon(Icons.check_circle_rounded,
                      color: _filledBorder, size: 18)
                else
                  Icon(Icons.keyboard_arrow_down,
                      color: Colors.grey.shade600, size: 20),
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
      case 'MFDatatypeLookup':
        {
          final hasValue = _formValues[property.id] != null;

          return _lookupShell(
            label: property.title,
            required: property.isRequired,
            hasValue: hasValue,
            isSingleSelect: true,
            onCreateNew: _resolveLookupCreateCallback(property),
            field: LookupField(
              title: property.title,
              propertyId: property.id,
              isMultiSelect: false,
              preSelectedIds: _formValues[property.id] == null
                  ? const []
                  : [(_formValues[property.id] as int)],
              injectedItems:
                  (_selectedLookupItems[property.id])?.cast<LookupItem>(),
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
                if (items.isNotEmpty) {
                  _triggerAutoSuggest(
                    selectedObjectId: items.first.id,
                    selectedObjectTypeId: property.typeId,
                    displayLabel: items.first.displayValue,
                  );
                }
              },
            ),
          );
        }

      case 'MFDatatypeMultiSelectLookup':
        {
          final selectedItems =
              _selectedLookupItems[property.id] ?? [];
          final selectedIds = (_formValues[property.id] is List)
              ? (_formValues[property.id] as List).cast<int>()
              : <int>[];

          final selectedTexts = selectedItems
              .map((e) => e.displayValue.toString())
              .toList();

          return _lookupShell(
            label: property.title,
            required: property.isRequired,
            hasValue: selectedIds.isNotEmpty,
            selectedTexts: selectedTexts,
            selectedItems: selectedItems,
            propertyId: property.id,
            onCreateNew: _resolveLookupCreateCallback(property),
            field: LookupField(
              key: ValueKey(
                ((_formValues[property.id] is List)
                        ? (_formValues[property.id] as List)
                            .cast<int>()
                        : <int>[])
                    .join(','),
              ),
              title: property.title,
              propertyId: property.id,
              isMultiSelect: true,
              preSelectedIds: (_formValues[property.id] is List)
                  ? (_formValues[property.id] as List).cast<int>()
                  : const [],
              injectedItems: selectedItems.cast<LookupItem>(),
              onSelected: (items) {
                setState(() {
                  _formValues[property.id] =
                      items.map((i) => i.id).toList();
                  _selectedLookupItems[property.id] = items;
                });
                if (items.isNotEmpty) {
                  _triggerAutoSuggest(
                    selectedObjectId: items.first.id,
                    selectedObjectTypeId: property.typeId,
                    displayLabel: items.first.displayValue,
                  );
                }
              },
            ),
          );
        }

      case 'MFDatatypeText':
        {
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
                if (property.isRequired &&
                    (value == null || value.trim().isEmpty)) {
                  return 'This field is required';
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _formValues[property.id] = value;
                  _fieldFilled[property.id] =
                      value.trim().isNotEmpty;
                });
              },
            ),
          );
        }

      case 'MFDatatypeMultiLineText':
        {
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
                if (property.isRequired &&
                    (value == null || value.trim().isEmpty)) {
                  return 'This field is required';
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _formValues[property.id] = value;
                  _fieldFilled[property.id] =
                      value.trim().isNotEmpty;
                });
              },
            ),
          );
        }

      case 'MFDatatypeInteger':
        {
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
                if (property.isRequired &&
                    (value == null || value.trim().isEmpty)) {
                  return 'This field is required';
                }
                if (value != null &&
                    value.trim().isNotEmpty &&
                    int.tryParse(value) == null) {
                  return 'Enter a valid number';
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _formValues[property.id] = int.tryParse(value);
                  _fieldFilled[property.id] =
                      value.trim().isNotEmpty;
                });
              },
            ),
          );
        }

      case 'MFDatatypeDate':
        return _dateField(property);

      case 'MFDatatypeTime':
        return _timeField(property);

      case 'MFDatatypeBoolean':
        {
          final current = _formValues[property.id];
          final bool? currentBool =
              current is bool ? current : null;
          final isFilled = currentBool != null;

          return _fieldShell(
            label: property.title,
            required: property.isRequired,
            field: GestureDetector(
              onTap: () async {
                final result =
                    await _showSearchableDropdown<bool>(
                  title: property.title,
                  items: const [true, false],
                  labelOf: (v) => v ? 'Yes' : 'No',
                  selected: currentBool,
                );
                if (result != null) {
                  setState(
                      () => _formValues[property.id] = result);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 14),
                decoration: BoxDecoration(
                  color:
                      isFilled ? _filledFill : AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFilled
                        ? _filledBorder
                        : Colors.grey.shade200,
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
                              ? AppColors.surfaceLight
                              : const Color(0xFF111827),
                          fontWeight: currentBool == null
                              ? FontWeight.w400
                              : FontWeight.w500,
                        ),
                      ),
                    ),
                    if (isFilled)
                      const Icon(Icons.check_circle_rounded,
                          color: _filledBorder, size: 18)
                    else
                      Icon(Icons.keyboard_arrow_down,
                          color: Colors.grey.shade600, size: 20),
                  ],
                ),
              ),
            ),
          );
        }

      default:
        {
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
                if (property.isRequired &&
                    (value == null || value.trim().isEmpty)) {
                  return 'This field is required';
                }
                return null;
              },
              onChanged: (value) {
                setState(() {
                  _formValues[property.id] = value;
                  _fieldFilled[property.id] =
                      value.trim().isNotEmpty;
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
              isError
                  ? Icons.error_outline
                  : Icons.check_circle_outline,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor:
            isError ? Colors.red.shade600 : Colors.green.shade600,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10)),
        margin: const EdgeInsets.all(16),
        duration: Duration(seconds: isError ? 4 : 2),
      ),
    );
  }

   // ── QUICK CREATE (inline "+" button on lookup fields) ──────────────────────

   /// Decides which inline "+" action (if any) applies to [property]:
  /// - null: user lacks permission to add (allowAdding == false)
  /// - full quick-create screen: the lookup targets an M-Files object type
  /// - lightweight add-value dialog: the lookup targets a plain value list
  VoidCallback? _resolveLookupCreateCallback(ClassProperty property) {
    if (!property.allowAdding) return null;
    if (property.objectTypeVL) {
      return () => _handleQuickCreate(property);
    }
    return () => _handleAddValueListItem(property);
  }

  /// Pushes a [DynamicFormScreen] scoped to [property]'s target object type
  /// so the user can create a related object without leaving this form.
  /// On success, selects the new object exactly as if chosen from the
  /// lookup's own search dialog.
  Future<void> _handleQuickCreate(ClassProperty property) async {
    final service = context.read<MFilesService>();

    if (property.typeId <= 0) {
      _showSnackBar(
        'Cannot create a new ${property.title}: target type unknown',
        isError: true,
      );
      return;
    }

    final targetType = service.objectTypes.firstWhere(
      (t) => t.id == property.typeId,
      orElse: () => VaultObjectType(
        id: property.typeId,
        displayName: property.title,
        isDocument: false,
        name: property.title,
      ),
    );

    final result = await Navigator.push<QuickCreateResult>(
      context,
      MaterialPageRoute(
        builder: (_) => DynamicFormScreen(
          objectType: targetType,
          isQuickCreate: true,
        ),
      ),
    );

    if (result == null || !mounted) return;

    if (result.objectId == null) {
      _showSnackBar(
        '${property.title} created — please select it from the search list',
      );
      return;
    }

    final newItem =
        LookupItem(id: result.objectId!, displayValue: result.displayValue);

    setState(() {
      if (property.propertyType == 'MFDatatypeMultiSelectLookup') {
        final existing = List<LookupItem>.from(
            (_selectedLookupItems[property.id] ?? const [])
                .cast<LookupItem>());
        if (!existing.any((i) => i.id == newItem.id)) {
          existing.add(newItem);
        }
        _selectedLookupItems[property.id] = existing;
        _formValues[property.id] = existing.map((i) => i.id).toList();
      } else {
        _selectedLookupItems[property.id] = [newItem];
        _formValues[property.id] = newItem.id;
      }
    });

    _showSnackBar('${property.title} created and selected');

    _triggerAutoSuggest(
      selectedObjectId: newItem.id,
      selectedObjectTypeId: property.typeId,
      displayLabel: newItem.displayValue,
    );
  }

  /// Opens a lightweight "add a value" dialog for lookups that point at a
  /// plain value list (not an M-Files object type) — just a name, no class
  /// or metadata, posted straight to AddValuelistItem.
  Future<void> _handleAddValueListItem(ClassProperty property) async {
    if (property.typeId <= 0) {
      _showSnackBar(
        'Cannot add a new ${property.title}: value list unknown',
        isError: true,
      );
      return;
    }

    final controller = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        insetPadding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Add new ${property.title}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF0F172A),
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter ${property.title.toLowerCase()}',
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.grey.shade200),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide:
                        const BorderSide(color: _primaryBlue, width: 2),
                  ),
                ),
                onSubmitted: (v) =>
                    Navigator.pop(dialogContext, v.trim()),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text('Cancel',
                        style: TextStyle(color: Colors.grey.shade700)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(
                        dialogContext, controller.text.trim()),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primaryBlue,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Add'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (name == null || name.isEmpty || !mounted) return;

    final service = context.read<MFilesService>();
    final newItem = await service.addValueListItem(
      valueListId: property.typeId,
      name: name,
    );

    if (!mounted) return;

    if (newItem == null) {
      _showSnackBar(
          'Failed to add value: ${service.error ?? "unknown error"}',
          isError: true);
      return;
    }

    setState(() {
      if (property.propertyType == 'MFDatatypeMultiSelectLookup') {
        final existing = List<LookupItem>.from(
            (_selectedLookupItems[property.id] ?? const [])
                .cast<LookupItem>());
        if (!existing.any((i) => i.id == newItem.id)) {
          existing.add(newItem);
        }
        _selectedLookupItems[property.id] = existing;
        _formValues[property.id] = existing.map((i) => i.id).toList();
      } else {
        _selectedLookupItems[property.id] = [newItem];
        _formValues[property.id] = newItem.id;
      }
    });

    _showSnackBar('${property.title} value added and selected');
  }

  // ── AUTO-SUGGEST ──────────────────────────────────────────────────────────

  Future<void> _triggerAutoSuggest({
    required int selectedObjectId,
    required int selectedObjectTypeId,
    required String displayLabel,
  }) async {
    debugPrint(
        '🔍 AutoSuggest: objectId=$selectedObjectId typeId=$selectedObjectTypeId');
    final service = context.read<MFilesService>();

    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted) return;

    showCheckingDialog(context);

    List<Map<String, dynamic>> fetched;
    try {
      fetched = await service.fetchObjectViewProps(
        objectId: selectedObjectId,
        objectTypeId: selectedObjectTypeId,
      );
    } catch (e) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      return;
    }
    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    // ── FIX: use _localProperties (the snapshot for the current class)
    //         instead of service.classProperties, which may have been
    //         overwritten by a different class fetch by this point.
    final formPropIds = _localProperties
        .where((p) => !p.isHidden && !p.isAutomatic)
        .map((p) => p.id)
        .toSet();

    final suggestions = extractSuggestions(
      fetchedProps: fetched,
      formPropertyIds: formPropIds,
    );

    debugPrint('🔍 AutoSuggest: fetched ${fetched.length} props, '
        'formPropIds=$formPropIds, suggestions=${suggestions.length}');

    if (suggestions.isEmpty || !mounted) return;

    final chosen = await showSuggestionsDialog(
      context: context,
      suggestions: suggestions,
      sourceLabel: displayLabel,
    );
    if (chosen == null || !mounted) return;
    _applySuggestions(chosen);
  }

  void _applySuggestions(List<SuggestedField> fields) {
    setState(() {
      for (final f in fields) {
        final type = f.propertyType.toLowerCase();

        if (type.contains('multiselectlookup')) {
          final ids = (f.rawValue as List).cast<int>();
          _formValues[f.propertyId] = ids;
          // Split display names by ', ' to pair with each id
          final names = f.displayValue.split(', ');
          _selectedLookupItems[f.propertyId] = List.generate(
            ids.length,
            (i) => LookupItem(
              id: ids[i],
              displayValue: i < names.length ? names[i] : ids[i].toString(),
            ),
          );
        } else if (type.contains('lookup')) {
          final id = f.rawValue as int;
          _formValues[f.propertyId] = id;
          _selectedLookupItems[f.propertyId] = [
            LookupItem(id: id, displayValue: f.displayValue),
          ];
        } else if (type.contains('text') ||
            type.contains('integer') ||
            type.contains('float')) {
          _formValues[f.propertyId] = f.rawValue.toString();
          _fieldFilled[f.propertyId] = true;
        } else if (type.contains('date')) {
          _formValues[f.propertyId] = f.rawValue;
        } else if (type.contains('boolean')) {
          _formValues[f.propertyId] = f.rawValue;
        } else {
          _formValues[f.propertyId] = f.rawValue;
        }
      }
    });
  }

  // ── SUBMIT ────────────────────────────────────────────────────────────────

  Future<void> _submitForm() async {
    if (_selectedClass == null) {
      _showSnackBar('Please select a class first', isError: true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final service = context.read<MFilesService>();

    // ── FIX: validate against _localProperties, not service.classProperties
    for (final prop in _localProperties
        .where((p) => !p.isHidden && !p.isAutomatic)) {
      if (!prop.isRequired) continue;
      final v = _formValues[prop.id];

      if (prop.propertyType == 'MFDatatypeLookup' && v == null) {
        _showSnackBar(
            'Required field "${prop.title}" is missing',
            isError: true);
        return;
      }
      if (prop.propertyType == 'MFDatatypeMultiSelectLookup' &&
          (v == null || (v is List && v.isEmpty))) {
        _showSnackBar(
            'Required field "${prop.title}" is missing',
            isError: true);
        return;
      }
      if (prop.propertyType == 'MFDatatypeDate' &&
          !(v is String && v.isNotEmpty)) {
        _showSnackBar(
            'Required field "${prop.title}" is missing',
            isError: true);
        return;
      }
      if (prop.propertyType == 'MFDatatypeTime' &&
          !(v is String && v.isNotEmpty)) {
        _showSnackBar(
            'Required field "${prop.title}" is missing',
            isError: true);
        return;
      }
    }

    String? uploadId;
    if (_currentObjectType.isDocument) {
      if (_selectedFile == null) {
        _showSnackBar('Please select a file for document objects',
            isError: true);
        return;
      }

      final file = File(_selectedFile!.path!);
      uploadId = await service.uploadFile(file);

      if (uploadId == null) {
        _showSnackBar('File upload failed', isError: true);
        return;
      }
    }

    final properties = <PropertyValueRequest>[];

    // ── FIX: use _localProperties for class-property checks
    final hasClassProperty =
        _localProperties.any((p) => p.id == 100);
    if (hasClassProperty) {
      properties.add(
        PropertyValueRequest(
          propId: 100,
          value: _selectedClass!.id.toString(),
          propertyType: 'MFDatatypeLookup',
        ),
      );
    }

    for (final prop in _localProperties) {
      if (prop.isAutomatic) continue;
      if (prop.id == 100 && hasClassProperty) continue;

      final value = _formValues[prop.id];
      if (value == null && !prop.isRequired) continue;

      if (value == null && prop.isRequired) {
        _showSnackBar(
            'Required field "${prop.title}" is missing',
            isError: true);
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

    // ── FIX: use _localProperties
    final classHasTitleProp =
        _localProperties.any((p) => p.id == 0);
    final hasTitleInPayload = properties.any((p) => p.propId == 0);

    if (classHasTitleProp && !hasTitleInPayload) {
      final title = (_formValues[0] ?? '').toString().trim();
      if (title.isEmpty) {
        _showSnackBar('Name or title is required', isError: true);
        return;
      }
      properties.add(PropertyValueRequest(
          propId: 0,
          value: title,
          propertyType: 'MFDatatypeText'));
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

    final result = await service.createObject(request);

    if (!mounted) return;

    if (result.success) {
      unawaited(service.fetchRecentObjects());
      _showSnackBar('Object created successfully!');

      if (widget.isQuickCreate) {
        Navigator.pop(
          context,
          QuickCreateResult(
            objectId: result.objectId,
            displayValue: _resolveQuickCreateDisplayValue(),
          ),
        );
      } else {
        Navigator.pop(context);
      }
    } else {
      _showSnackBar('Failed to create object: ${service.error}',
          isError: true);
    }
  } // end _submitForm

  /// Best label for the object just created, used to populate the lookup
  /// field that launched this quick-create screen. Prefers the Title
  /// property (id 0); falls back to the class/object-type name.
  String _resolveQuickCreateDisplayValue() {
    final titleVal = _formValues[0];
    if (titleVal is String && titleVal.trim().isNotEmpty) {
      return titleVal.trim();
    }
    return _selectedClass?.displayName ?? _currentObjectType.displayName;
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: AppColors.surfaceLight,
        appBar: AppBar(
          backgroundColor: AppColors.primary,
          elevation: 0,
          toolbarHeight: 64,
          titleSpacing: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded,
                color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          title: Padding(
            padding:
                const EdgeInsets.only(left: 12.0, right: 8.0),
            child: Container(
              padding: const EdgeInsets.all(4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/alignsysnew.png',
                  height: 36,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        body: NetworkBanner(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Consumer<MFilesService>(
              builder: (context, service, _) {
                final objectClasses = service.objectClasses
                    .where((cls) =>
                        cls.objectTypeId == _currentObjectType.id)
                    .toList();

                // ── FIX: build visibleProperties from _localProperties
                //         (the snapshot tied to _selectedClass), NOT from
                //         service.classProperties which is a shared global.
                final visibleProperties = _localProperties
                    .where((p) => !p.isHidden && !p.isAutomatic)
                    .toList()
                  ..sort((a, b) {
                    if (a.id == 0) return -1;
                    if (b.id == 0) return 1;
                    return 0;
                  });

                return ListView(
                  padding: const EdgeInsets.all(16),
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
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
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
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
                                      onTap: widget.isQuickCreate
                                          ? null
                                          : () async {
                                              final result =
                                                  await _showSearchableDropdown
                                                      <VaultObjectType>(
                                                title:
                                                    'Select Object Type',
                                                items: service.objectTypes,
                                                labelOf: (t) =>
                                                    t.displayName,
                                                selected: _currentObjectType,
                                              );
                                              if (result != null &&
                                                  result.id !=
                                                      _currentObjectType
                                                          .id) {
                                                await _onObjectTypeChanged(
                                                    result);
                                              }
                                            },
                                      child: Row(
                                        mainAxisSize:
                                            MainAxisSize.min,
                                        children: [
                                          Text(
                                            'Create ${_currentObjectType.displayName}',
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight:
                                                  FontWeight.w800,
                                              color:
                                                  Color(0xFF0F172A),
                                              letterSpacing: 0.2,
                                            ),
                                          ),
                                          if (!widget.isQuickCreate) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 3),
                                              decoration: BoxDecoration(
                                                color: _primaryBlue
                                                    .withOpacity(0.1),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        6),
                                              ),
                                              child: const Row(
                                                mainAxisSize:
                                                    MainAxisSize.min,
                                                children: [
                                                  Text(
                                                    'Change',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight:
                                                          FontWeight
                                                              .w700,
                                                      color:
                                                          _primaryBlue,
                                                    ),
                                                  ),
                                                  SizedBox(width: 2),
                                                  Icon(
                                                      Icons
                                                          .swap_horiz_rounded,
                                                      size: 12,
                                                      color:
                                                          _primaryBlue),
                                                ],
                                              ),
                                            ),
                                          ],
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
                          if (_isLoadingClasses)
                            Column(
                              children: [
                                const LinearProgressIndicator(
                                  minHeight: 3,
                                  backgroundColor:
                                      Color(0xFFE8EEF5),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(
                                          _primaryBlue),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'Loading classes...',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.grey.shade600),
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
                                      await _showSearchableDropdown<
                                          ObjectClass>(
                                    title: 'Select Class',
                                    items: objectClasses,
                                    labelOf: (c) => c.displayName,
                                    selected: _selectedClass,
                                  );
                                  if (result != null) {
                                    _onClassSelected(result);
                                  }
                                },
                                child: AnimatedContainer(
                                  duration:
                                      const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14, vertical: 14),
                                  decoration: BoxDecoration(
                                    color: _selectedClass != null
                                        ? _filledFill
                                        : AppColors.surfaceLight,
                                    borderRadius:
                                        BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedClass != null
                                          ? _filledBorder
                                          : Colors.grey.shade200,
                                      width:
                                          _selectedClass != null
                                              ? 1.5
                                              : 1,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          _selectedClass
                                                  ?.displayName ??
                                              'Tap to select class',
                                          style: _inputStyle.copyWith(
                                            color:
                                                _selectedClass != null
                                                    ? const Color(
                                                        0xFF111827)
                                                    : AppColors
                                                        .surfaceLight,
                                            fontWeight:
                                                _selectedClass != null
                                                    ? FontWeight.w500
                                                    : FontWeight.w400,
                                          ),
                                        ),
                                      ),
                                      if (_selectedClass != null)
                                        const Icon(
                                            Icons.check_circle_rounded,
                                            color: _filledBorder,
                                            size: 18)
                                      else
                                        Icon(
                                            Icons.keyboard_arrow_down,
                                            color:
                                                Colors.grey.shade600,
                                            size: 20),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ── File upload (documents only) ──
                    if (_selectedClass != null &&
                        _currentObjectType.isDocument) ...[
                      _card(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _sectionHeader('File upload',
                                subtitle:
                                    'Attach the document file.'),
                            const SizedBox(height: 14),
                            _topLabel('File', required: true),
                            AnimatedContainer(
                              duration:
                                  const Duration(milliseconds: 200),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: _selectedFile != null
                                    ? _filledFill
                                    : AppColors.surfaceLight,
                                borderRadius:
                                    BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedFile != null
                                      ? _filledBorder
                                      : Colors.grey.shade200,
                                  width:
                                      _selectedFile != null ? 1.5 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _selectedFile != null
                                        ? Icons
                                            .insert_drive_file_rounded
                                        : Icons
                                            .cloud_upload_outlined,
                                    color: _selectedFile != null
                                        ? _primaryBlue
                                        : Colors.grey.shade400,
                                    size: 22,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _selectedFileName ??
                                              'No file selected',
                                          maxLines: 1,
                                          overflow:
                                              TextOverflow.ellipsis,
                                          style: _inputStyle.copyWith(
                                            color: _selectedFile !=
                                                    null
                                                ? const Color(
                                                    0xFF111827)
                                                : AppColors
                                                    .surfaceLight,
                                            fontWeight:
                                                _selectedFile != null
                                                    ? FontWeight.w500
                                                    : FontWeight.w400,
                                          ),
                                        ),
                                        if (_selectedFile !=
                                            null) ...[
                                          const SizedBox(height: 2),
                                          Text(
                                            'Ready to upload',
                                            style: TextStyle(
                                                fontSize: 12,
                                                color: Colors
                                                    .green.shade600),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    onPressed: _pickFile,
                                    icon: const Icon(
                                        Icons.folder_open_rounded,
                                        size: 16),
                                    label: const Text('Browse'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: _primaryBlue,
                                      foregroundColor: Colors.white,
                                      padding:
                                          const EdgeInsets.symmetric(
                                              horizontal: 16,
                                              vertical: 12),
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(
                                                  10)),
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
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              _sectionHeader('Properties',
                                  subtitle:
                                      'Fill in the required details below.'),
                              const SizedBox(height: 14),

                              // Show spinner while the fetch for this class
                              // is still in flight (_localProperties is empty
                              // but a class IS selected).
                              if (service.isLoading &&
                                  _localProperties.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 24),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        const CircularProgressIndicator(),
                                        const SizedBox(height: 16),
                                        Text(
                                          'Loading properties...',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors
                                                  .grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else if (visibleProperties.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 24),
                                  child: Center(
                                    child: Column(
                                      children: [
                                        Container(
                                          padding:
                                              const EdgeInsets.all(16),
                                          decoration: BoxDecoration(
                                            color: Colors.grey.shade100,
                                            shape: BoxShape.circle,
                                          ),
                                          child: Icon(
                                              Icons.info_outline,
                                              size: 32,
                                              color: Colors
                                                  .grey.shade400),
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'No properties to configure',
                                          style: TextStyle(
                                              fontSize: 13,
                                              color: Colors
                                                  .grey.shade600),
                                        ),
                                      ],
                                    ),
                                  ),
                                )
                              else
                                Column(
                                  children: List.generate(
                                    visibleProperties.length * 2 - 1,
                                    (index) {
                                      if (index.isOdd) {
                                        return const Padding(
                                          padding: EdgeInsets.symmetric(
                                              vertical: 12),
                                          child: Divider(
                                            height: 1,
                                            thickness: 1.5,
                                            color: Color(0xFFCBD5E1),
                                          ),
                                        );
                                      }
                                      final p = visibleProperties[
                                          index ~/ 2];
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
                          onPressed: service.isLoading
                              ? null
                              : _submitForm,
                          icon: service.isLoading
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor:
                                        AlwaysStoppedAnimation<Color>(
                                            Colors.white),
                                  ),
                                )
                              : const Icon(
                                  Icons.check_circle_rounded,
                                  size: 20),
                          label: Text(
                            service.isLoading
                                ? 'Creating...'
                                : 'Create Object',
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
                                borderRadius:
                                    BorderRadius.circular(12)),
                            elevation:
                                service.isLoading ? 0 : 2,
                            shadowColor:
                                _primaryBlue.withOpacity(0.3),
                            disabledBackgroundColor:
                                Colors.grey.shade300,
                            disabledForegroundColor:
                                Colors.grey.shade600,
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
        ),
      ),
    );
  }
} 