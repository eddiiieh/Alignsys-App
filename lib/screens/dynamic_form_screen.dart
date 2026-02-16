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
  // NEW: Store selected lookup items for display purposes
  final Map<int, List<dynamic>> _selectedLookupItems = {};

  File? _selectedFile;
  String? _selectedFileName;

  ObjectClass? _selectedClass;

  bool _isLoadingClasses = false;

  static final DateFormat _apiDateFmt = DateFormat('yyyy-MM-dd');
  static final DateFormat _uiDateFmt = DateFormat('dd MMM yyyy');
  static final DateFormat _uiTimeFmt = DateFormat('HH:mm');

  @override
  void initState() {
    super.initState();
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

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _sectionHeader(String title, {IconData? icon}) {
    return Row(
      children: [
        if (icon != null) ...[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF072F5F).withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 18, color: const Color.fromRGBO(25, 76, 129, 1)),
          ),
          const SizedBox(width: 10),
        ],
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1A1A1A),
          ),
        ),
      ],
    );
  }

  Widget _labelWithRequired(String label, bool required) {
    if (!required) return Text(label);
    return RichText(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: Colors.black87),
        children: const [
          TextSpan(text: ' *', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  InputDecoration _deco(String label, {String? helper, bool required = false}) {
    return InputDecoration(
      label: _labelWithRequired(label, required),
      helperText: helper,
      isDense: true,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF072F5F), width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red.shade300),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Colors.red, width: 2),
      ),
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

  Widget _dropdownShell({
    required String label,
    required bool required,
    required bool hasValue,
    required String valueText,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: RichText(
            text: TextSpan(
              text: label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
              children: required
                  ? const [
                      TextSpan(
                        text: ' *',
                        style: TextStyle(color: Colors.red, fontWeight: FontWeight.w700),
                      )
                    ]
                  : const [],
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: child,
                ),
              ),
              if (valueText.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF072F5F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      valueText,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF072F5F),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        _requiredHint(required && !hasValue),
      ],
    );
  }

  Future<void> _onClassSelected(ObjectClass? objectClass) async {
    if (objectClass == null) return;

    setState(() {
      _selectedClass = objectClass;
      _formValues.clear();
      _selectedLookupItems.clear(); // Clear lookup items too
      _selectedFile = null;
      _selectedFileName = null;
    });

    await context.read<MFilesService>().fetchClassProperties(widget.objectType.id, objectClass.id);
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
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: const Color(0xFF072F5F),
              ),
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
          colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: const Color(0xFF072F5F),
              ),
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

  Widget _dateField(ClassProperty p) {
    final v = _formValues[p.id];
    final has = v is String && v.isNotEmpty;

    return InkWell(
      onTap: () => _pickDate(p),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: has ? const Color(0xFF072F5F).withOpacity(0.3) : Colors.grey.shade200,
            width: has ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: has 
                        ? const Color(0xFF072F5F).withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.calendar_today_rounded,
                    size: 18,
                    color: has 
                        ? const Color(0xFF072F5F)
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    has ? _formatDateForUi(v) : 'Tap to select date',
                    style: TextStyle(
                      color: has ? const Color(0xFF1A1A1A) : Colors.grey.shade600,
                      fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _timeField(ClassProperty p) {
    final v = _formValues[p.id];
    final has = v is String && v.isNotEmpty;

    return InkWell(
      onTap: () => _pickTime(p),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: has ? const Color(0xFF072F5F).withOpacity(0.3) : Colors.grey.shade200,
            width: has ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              p.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: has 
                        ? const Color(0xFF072F5F).withOpacity(0.1)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(
                    Icons.access_time_rounded,
                    size: 18,
                    color: has 
                        ? const Color(0xFF072F5F)
                        : Colors.grey.shade600,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    has ? _formatTimeForUi(v) : 'Tap to select time',
                    style: TextStyle(
                      color: has ? const Color(0xFF1A1A1A) : Colors.grey.shade600,
                      fontWeight: has ? FontWeight.w600 : FontWeight.w400,
                      fontSize: 15,
                    ),
                  ),
                ),
                Icon(
                  Icons.keyboard_arrow_down,
                  color: Colors.grey.shade600,
                  size: 20,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(ClassProperty property) {
    switch (property.propertyType) {
      case 'MFDatatypeLookup':
        final hasValue = _formValues[property.id] != null;
        return _dropdownShell(
          label: property.title,
          required: property.isRequired,
          hasValue: hasValue,
          valueText: hasValue ? 'Selected' : '',
          child: LookupField(
            title: property.title,
            propertyId: property.id,
            isMultiSelect: false,
            onSelected: (selectedItems) {
              setState(() {
                if (selectedItems.isNotEmpty) {
                  _formValues[property.id] = selectedItems.first.id;
                  _selectedLookupItems[property.id] = selectedItems;
                } else {
                  _formValues[property.id] = null;
                  _selectedLookupItems.remove(property.id);
                }
              });
            },
          ),
        );

      case 'MFDatatypeMultiSelectLookup':
        final selectedItems = _selectedLookupItems[property.id] ?? [];
        final selected = (_formValues[property.id] is List)
            ? (_formValues[property.id] as List).cast<int>()
            : <int>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dropdownShell(
              label: property.title,
              required: property.isRequired,
              hasValue: selected.isNotEmpty,
              valueText: selected.isEmpty ? '' : '${selected.length}',
              child: LookupField(
                title: property.title,
                propertyId: property.id,
                isMultiSelect: true,
                onSelected: (items) {
                  setState(() {
                    _formValues[property.id] = items.map((i) => i.id).toList();
                    _selectedLookupItems[property.id] = items;
                  });
                },
              ),
            ),
            // Show selected items below the dropdown
            if (selectedItems.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: selectedItems.map((item) {
                  final displayName = item.displayValue;
                  
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF072F5F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: const Color(0xFF072F5F).withOpacity(0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle,
                          size: 14,
                          color: const Color(0xFF072F5F),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF072F5F),
                          ),
                        ),
                        const SizedBox(width: 4),
                        InkWell(
                          onTap: () {
                            setState(() {
                              // Remove from both lists
                              final updatedItems = List.from(selectedItems);
                              updatedItems.removeWhere((i) => i.id == item.id);
                              
                              _selectedLookupItems[property.id] = updatedItems;
                              _formValues[property.id] = updatedItems.map((i) => i.id).toList();
                            });
                          },
                          child: Icon(
                            Icons.close,
                            size: 14,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        );

      case 'MFDatatypeText':
        return TextFormField(
          decoration: _deco(property.title, required: property.isRequired),
          style: const TextStyle(fontSize: 14),
          validator: (value) {
            if (property.isRequired && (value == null || value.trim().isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
          onChanged: (value) => _formValues[property.id] = value,
        );

      case 'MFDatatypeMultiLineText':
        return TextFormField(
          decoration: _deco(property.title, required: property.isRequired),
          style: const TextStyle(fontSize: 14),
          maxLines: 4,
          validator: (value) {
            if (property.isRequired && (value == null || value.trim().isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
          onChanged: (value) => _formValues[property.id] = value,
        );

      case 'MFDatatypeInteger':
        return TextFormField(
          decoration: _deco(property.title, required: property.isRequired),
          style: const TextStyle(fontSize: 14),
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
          onChanged: (value) => _formValues[property.id] = int.tryParse(value),
        );

      case 'MFDatatypeDate':
        return _dateField(property);

      case 'MFDatatypeTime':
        return _timeField(property);

      case 'MFDatatypeBoolean':
        final current = _formValues[property.id];
        final bool? currentBool = current is bool ? current : null;

        return DropdownButtonFormField<bool>(
          value: currentBool,
          decoration: _deco(property.title, required: property.isRequired),
          icon: const Icon(Icons.keyboard_arrow_down),
          items: const [
            DropdownMenuItem(value: true, child: Text('Yes')),
            DropdownMenuItem(value: false, child: Text('No')),
          ],
          onChanged: (v) => setState(() => _formValues[property.id] = v),
          validator: (v) {
            if (property.isRequired && v == null) return 'This field is required';
            return null;
          },
        );

      default:
        return TextFormField(
          decoration: _deco(property.title, required: property.isRequired),
          style: const TextStyle(fontSize: 14),
          validator: (value) {
            if (property.isRequired && (value == null || value.trim().isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
          onChanged: (value) => _formValues[property.id] = value,
        );
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

    // manual required check for lookup fields
    for (final prop in service.classProperties.where((p) => !p.isHidden && !p.isAutomatic)) {
      if (!prop.isRequired) continue;

      final v = _formValues[prop.id];
      if (prop.propertyType == 'MFDatatypeLookup' && v == null) {
        _showSnackBar('Required field "${prop.title}" is missing', isError: true);
        return;
      }

      if (prop.propertyType == 'MFDatatypeMultiSelectLookup' && (v == null || (v is List && v.isEmpty))) {
        _showSnackBar('Required field "${prop.title}" is missing', isError: true);
        return;
      }
    }

    String? uploadId;
    if (widget.objectType.isDocument) {
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
      objectID: widget.objectType.id,
      objectTypeID: widget.objectType.id,
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
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(10),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/alignsysop.png',
                  height: 28,
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
        ),
        body: Consumer<MFilesService>(
          builder: (context, service, _) {
            final objectClasses = service.objectClasses
                .where((cls) => cls.objectTypeId == widget.objectType.id)
                .toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header Card
                _card(
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF072F5F).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          widget.objectType.isDocument
                              ? Icons.description_rounded
                              : Icons.folder_rounded,
                          color: const Color.fromRGBO(25, 76, 129, 1),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create ${widget.objectType.displayName}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1A1A1A),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedClass != null
                                  ? 'Class: ${_selectedClass!.displayName}'
                                  : 'Select a class to continue',
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Class Selection Card
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _sectionHeader('Select Class', icon: Icons.category_rounded),
                      const SizedBox(height: 14),
                      if (_isLoadingClasses)
                        Column(
                          children: [
                            const LinearProgressIndicator(
                              minHeight: 3,
                              backgroundColor: Color(0xFFE8EEF5),
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF072F5F)),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Loading classes...',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        )
                      else
                        DropdownButtonFormField<int>(
                          value: _selectedClass?.id,
                          decoration: _deco('Class'),
                          icon: const Icon(Icons.keyboard_arrow_down),
                          isExpanded: true,
                          items: objectClasses
                              .map((c) => DropdownMenuItem<int>(
                                    value: c.id,
                                    child: Text(
                                      c.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 14),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (id) {
                            if (id == null) return;
                            final chosen = objectClasses.firstWhere((c) => c.id == id);
                            _onClassSelected(chosen);
                          },
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // File Upload Card (for documents)
                if (_selectedClass != null && widget.objectType.isDocument) ...[
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _sectionHeader('File Upload', icon: Icons.upload_file_rounded),
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _selectedFile != null
                                  ? const Color(0xFF072F5F).withOpacity(0.3)
                                  : Colors.grey.shade200,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedFile != null
                                    ? Icons.insert_drive_file_rounded
                                    : Icons.cloud_upload_outlined,
                                color: _selectedFile != null
                                    ? const Color(0xFF072F5F)
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
                                      style: TextStyle(
                                        color: _selectedFile != null
                                            ? const Color(0xFF1A1A1A)
                                            : Colors.grey.shade600,
                                        fontWeight: _selectedFile != null
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        fontSize: 14,
                                      ),
                                    ),
                                    if (_selectedFile != null) ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        'Ready to upload',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.green.shade600,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              ElevatedButton.icon(
                                onPressed: _pickFile,
                                icon: const Icon(Icons.folder_open_rounded, size: 16),
                                label: const Text('Browse'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: const Color(0xFF072F5F),
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  elevation: 0,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

                // Properties Form Card
                if (_selectedClass != null) ...[
                  _card(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _sectionHeader('Properties', icon: Icons.view_list_rounded),
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
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else if (service.classProperties
                              .where((p) => !p.isHidden && !p.isAutomatic)
                              .isEmpty)
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
                                      child: Icon(
                                        Icons.info_outline,
                                        size: 32,
                                        color: Colors.grey.shade400,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No properties to configure',
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            )
                          else
                            ...service.classProperties
                                .where((p) => !p.isHidden && !p.isAutomatic)
                                .map((p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 14),
                                      child: _buildField(p),
                                    )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Submit Button
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
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
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
                        backgroundColor: const Color(0xFF072F5F),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: service.isLoading ? 0 : 2,
                        shadowColor: const Color(0xFF072F5F).withOpacity(0.3),
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