import 'dart:convert';
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

  File? _selectedFile;
  String? _selectedFileName;

  ObjectClass? _selectedClass;

  bool _isLoadingClasses = false;

  // Date formats required by your API/web client behavior
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

  // ---------- UI helpers (match ObjectDetails structure) ----------
  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: child,
    );
  }

  InputDecoration _deco(String label, {String? helper}) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      isDense: true,
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade300),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF0A1541), width: 2),
      ),
    );
  }

  Widget _requiredHint(bool show) {
    if (!show) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text('This field is required', style: TextStyle(color: Colors.red.shade600, fontSize: 12)),
    );
  }

  // Dropdown-looking shell for Lookup/MultiSelectLookup (no new endpoint required)
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
        Text(
          label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: child,
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: Row(
                  children: [
                    Text(
                      hasValue ? valueText : 'Select',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
                  ],
                ),
              ),
            ],
          ),
        ),
        _requiredHint(required && !hasValue),
      ],
    );
  }

  // ---------- Class selection ----------
  Future<void> _onClassSelected(ObjectClass? objectClass) async {
    if (objectClass == null) return;

    setState(() {
      _selectedClass = objectClass;
      _formValues.clear();
      _selectedFile = null;
      _selectedFileName = null;
    });

    await context.read<MFilesService>().fetchClassProperties(
          widget.objectType.id,
          objectClass.id,
        );
  }

  // ---------- File ----------
  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles();
    if (result == null) return;

    setState(() {
      _selectedFile = File(result.files.single.path!);
      _selectedFileName = result.files.single.name;
    });
  }

  // ---------- Date/Time ----------
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
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: const Color(0xFF0A1541)),
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
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: const Color(0xFF0A1541)),
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
      child: InputDecorator(
        decoration: _deco(p.title),
        child: Row(
          children: [
            Expanded(
              child: Text(
                has ? _formatDateForUi(v) : 'Select',
                style: TextStyle(color: has ? Colors.black87 : Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
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
      child: InputDecorator(
        decoration: _deco(p.title),
        child: Row(
          children: [
            Expanded(
              child: Text(
                has ? _formatTimeForUi(v) : 'Select',
                style: TextStyle(color: has ? Colors.black87 : Colors.grey.shade600, fontWeight: FontWeight.w600),
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600),
          ],
        ),
      ),
    );
  }

  // ---------- Fields ----------
  Widget _buildField(ClassProperty property) {
    switch (property.propertyType) {
      // ✅ dropdown-looking, uses existing LookupField selection flow
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
                _formValues[property.id] = selectedItems.isNotEmpty ? selectedItems.first.id : null;
              });
            },
          ),
        );

      case 'MFDatatypeMultiSelectLookup':
        final selected = (_formValues[property.id] is List)
            ? (_formValues[property.id] as List).cast<int>()
            : <int>[];

        return _dropdownShell(
          label: property.title,
          required: property.isRequired,
          hasValue: selected.isNotEmpty,
          valueText: selected.isEmpty ? '' : '${selected.length} selected',
          child: LookupField(
            title: property.title,
            propertyId: property.id,
            isMultiSelect: true,
            onSelected: (selectedItems) {
              setState(() {
                _formValues[property.id] = selectedItems.map((i) => i.id).toList();
              });
            },
          ),
        );

      case 'MFDatatypeText':
        return TextFormField(
          decoration: _deco(property.title),
          validator: (value) {
            if (property.isRequired && (value == null || value.trim().isEmpty)) return 'This field is required';
            return null;
          },
          onChanged: (value) => _formValues[property.id] = value,
        );

      case 'MFDatatypeMultiLineText':
        return TextFormField(
          decoration: _deco(property.title),
          maxLines: 4,
          validator: (value) {
            if (property.isRequired && (value == null || value.trim().isEmpty)) return 'This field is required';
            return null;
          },
          onChanged: (value) => _formValues[property.id] = value,
        );

      case 'MFDatatypeInteger':
        return TextFormField(
          decoration: _deco(property.title),
          keyboardType: TextInputType.number,
          validator: (value) {
            if (property.isRequired && (value == null || value.trim().isEmpty)) return 'This field is required';
            if (value != null && value.trim().isNotEmpty && int.tryParse(value) == null) return 'Enter a valid number';
            return null;
          },
          onChanged: (value) => _formValues[property.id] = int.tryParse(value),
        );

      case 'MFDatatypeDate':
        return _dateField(property);

      case 'MFDatatypeTime':
        return _timeField(property);

      // ✅ boolean dropdown (Yes/No) — applies to Car “Purchased brand new”
      case 'MFDatatypeBoolean':
        final current = _formValues[property.id];
        final bool? currentBool = current is bool ? current : null;

        return DropdownButtonFormField<bool>(
          value: currentBool,
          decoration: _deco(property.title),
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
          decoration: _deco(property.title),
          validator: (value) {
            if (property.isRequired && (value == null || value.trim().isEmpty)) return 'This field is required';
            return null;
          },
          onChanged: (value) => _formValues[property.id] = value,
        );
    }
  }

  // ---------- Submit ----------
  Future<void> _submitForm() async {
    if (_selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Please select a class first'), backgroundColor: Colors.orange.shade600),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final service = context.read<MFilesService>();

    // Manual required check for lookup fields (since LookupField isn't a FormField)
    for (final prop in service.classProperties.where((p) => !p.isHidden && !p.isAutomatic)) {
      if (!prop.isRequired) continue;

      final v = _formValues[prop.id];
      if (prop.propertyType == 'MFDatatypeLookup' && v == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Required field "${prop.title}" is missing'), backgroundColor: Colors.red.shade600),
        );
        return;
      }

      if (prop.propertyType == 'MFDatatypeMultiSelectLookup' && (v == null || (v is List && v.isEmpty))) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Required field "${prop.title}" is missing'), backgroundColor: Colors.red.shade600),
        );
        return;
      }
    }

    // Required file check for document objects
    String? uploadId;
    if (widget.objectType.isDocument) {
      if (_selectedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('Please select a file for document objects'), backgroundColor: Colors.red.shade600),
        );
        return;
      }
      uploadId = await service.uploadFile(_selectedFile!);
      if (uploadId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: const Text('File upload failed'), backgroundColor: Colors.red.shade600),
        );
        return;
      }
    }

    final List<PropertyValueRequest> properties = [];

    // Add Class property ONLY if the class exposes it (propId 100)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Required field "${prop.title}" is missing'), backgroundColor: Colors.red.shade600),
        );
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

    // Add Name/Title (propId 0) ONLY if this class exposes it
    final classHasTitleProp = service.classProperties.any((p) => p.id == 0);
    final hasTitleInPayload = properties.any((p) => p.propId == 0);

    if (classHasTitleProp && !hasTitleInPayload) {
      final title = (_formValues[0] ?? '').toString().trim();
      if (title.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Name or title is required'), backgroundColor: Colors.red),
        );
        return;
      }
      properties.add(PropertyValueRequest(propId: 0, value: title, propertyType: 'MFDatatypeText'));
    }

    final request = ObjectCreationRequest(
      objectID: widget.objectType.id,
      objectTypeID: widget.objectType.id,
      classID: _selectedClass!.id,
      properties: properties,
      vaultGuid: service.vaultGuid,
      userID: service.mfilesUserId ?? 0,
      uploadId: uploadId,
    );

    final success = await service.createObject(request);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: const Text('Object created successfully!'), backgroundColor: Colors.green.shade600),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create object: ${service.error}'),
          backgroundColor: Colors.red.shade600,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  // ---------- Screen ----------
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
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () => Navigator.pop(context),
          ),
          // ✅ keep it like your original: logo only, correct margin, no extra title text
          title: Padding(
            padding: const EdgeInsets.only(left: 12.0, right: 8.0),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/alignsysop.png',
                height: 32,
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
        body: Consumer<MFilesService>(
          builder: (context, service, _) {
            final objectClasses = service.objectClasses.where((cls) => cls.objectTypeId == widget.objectType.id).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header card
                _card(
                  child: Row(
                    children: [
                      Icon(
                        widget.objectType.isDocument ? Icons.description_outlined : Icons.folder_outlined,
                        color: const Color(0xFF0A1541),
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create ${widget.objectType.displayName}',
                              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedClass != null ? 'Class: ${_selectedClass!.displayName}' : 'Select a class to continue',
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // ✅ Select Class dropdown like your screenshot
                _card(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Select Class', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 10),
                      if (_isLoadingClasses)
                        const LinearProgressIndicator(minHeight: 2)
                      else
                        DropdownButtonFormField<int>(
                          value: _selectedClass?.id,
                          decoration: _deco('Class'),
                          icon: const Icon(Icons.keyboard_arrow_down),
                          isExpanded: true,
                          items: objectClasses
                              .map((c) => DropdownMenuItem<int>(
                                    value: c.id,
                                    child: Text(c.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
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

                const SizedBox(height: 12),

                if (_selectedClass != null && widget.objectType.isDocument) ...[
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('File Upload', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _selectedFileName ?? 'No file selected',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.grey.shade700),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton.icon(
                              onPressed: _pickFile,
                              icon: const Icon(Icons.folder_open, size: 18),
                              label: const Text('Browse'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF0A1541),
                                foregroundColor: Colors.white,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                elevation: 0,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                if (_selectedClass != null) ...[
                  _card(
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Properties', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 10),

                          if (service.isLoading && service.classProperties.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(child: CircularProgressIndicator()),
                            )
                          else
                            ...service.classProperties
                                .where((p) => !p.isHidden && !p.isAutomatic)
                                .map((p) => Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: _buildField(p),
                                    )),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      onPressed: service.isLoading ? null : _submitForm,
                      icon: service.isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Icon(Icons.save, size: 20),
                      label: Text(
                        service.isLoading ? 'Creating...' : 'Create Object',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A1541),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 16),
              ],
            );
          },
        ),
      ),
    );
  }
}
