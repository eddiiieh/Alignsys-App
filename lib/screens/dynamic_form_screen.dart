import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mfiles_app/widgets/lookup_field.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/mfiles_service.dart';
import '../models/vault_object_type.dart';
import '../models/object_class.dart';
import '../models/object_creation_request.dart';
import '../models/class_property.dart';

class DynamicFormScreen extends StatefulWidget {
  const DynamicFormScreen({
    super.key,
    required this.objectType,
    this.objectClass, // Made optional - user will select it
  });

  final VaultObjectType objectType;
  final ObjectClass? objectClass; // Optional now

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
  bool _classesLoaded = false;

  @override
  void initState() {
    super.initState();
    _selectedClass = widget.objectClass; // Use provided class if available
    
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final service = context.read<MFilesService>();
      
      // Fetch classes for this object type
      setState(() {
        _isLoadingClasses = true;
      });
      
      await service.fetchObjectClasses(widget.objectType.id);
      
      setState(() {
        _isLoadingClasses = false;
        _classesLoaded = true;
      });
      
      // If a class is selected, fetch its properties
      if (_selectedClass != null) {
        await service.fetchClassProperties(
          widget.objectType.id,
          _selectedClass!.id,
        );
      }
    });
  }

  Future<void> _onClassSelected(ObjectClass objectClass) async {
    setState(() {
      _selectedClass = objectClass;
      _formValues.clear(); // Clear form when class changes
    });
    
    // Fetch properties for the selected class
    await context.read<MFilesService>().fetchClassProperties(
      widget.objectType.id,
      objectClass.id,
    );
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles();
    if (result != null) {
      setState(() {
        _selectedFile = File(result.files.single.path!);
        _selectedFileName = result.files.single.name;
      });
    }
  }

  Future<void> _pickDate(ClassProperty property) async {
    final date = await showDatePicker(
      context: context,
      initialDate: _formValues[property.id] != null 
          ? DateTime.parse(_formValues[property.id])
          : DateTime.now(),
      firstDate: DateTime(1800),
      lastDate: DateTime(2200),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF0A1541),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (date != null) {
      setState(() {
        _formValues[property.id] = date.toIso8601String();
      });
    }
  }

  Future<void> _pickTime(ClassProperty property) async {
    final time = await showTimePicker(
      context: context,
      initialTime: _formValues[property.id] != null 
          ? TimeOfDay.fromDateTime(DateTime.parse(_formValues[property.id]))
          : TimeOfDay.now(),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(
              primary: const Color(0xFF0A1541),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (time != null) {
      final now = DateTime.now();
      final combinedDateTime = DateTime(
        now.year,
        now.month,
        now.day,
        time.hour,
        time.minute,
      );
      
      setState(() {
        _formValues[property.id] = combinedDateTime.toIso8601String();
      });
    }
  }

  String _formatDate(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return DateFormat('MMM dd, yyyy').format(dateTime);
    } catch (e) {
      return 'Invalid date';
    }
  }

  String _formatTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      return DateFormat('hh:mm a').format(dateTime);
    } catch (e) {
      return 'Invalid time';
    }
  }

  Widget _buildDateField(ClassProperty property) {
    final hasValue = _formValues[property.id] != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          property.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _pickDate(property),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  color: hasValue ? const Color(0xFF0A1541) : Colors.grey.shade500,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasValue
                        ? _formatDate(_formValues[property.id])
                        : 'Select date',
                    style: TextStyle(
                      color: hasValue ? Colors.black87 : Colors.grey.shade500,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (hasValue)
                  IconButton(
                    icon: Icon(Icons.clear, color: Colors.grey.shade500, size: 20),
                    onPressed: () {
                      setState(() {
                        _formValues[property.id] = null;
                      });
                    },
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ),
        if (property.isRequired && !hasValue)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This field is required',
              style: TextStyle(
                color: Colors.red.shade600,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildTimeField(ClassProperty property) {
    final hasValue = _formValues[property.id] != null;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          property.title,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        InkWell(
          onTap: () => _pickTime(property),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(8),
              color: Colors.grey.shade50,
            ),
            child: Row(
              children: [
                Icon(
                  Icons.access_time,
                  color: hasValue ? const Color(0xFF0A1541) : Colors.grey.shade500,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    hasValue
                        ? _formatTime(_formValues[property.id])
                        : 'Select time',
                    style: TextStyle(
                      color: hasValue ? Colors.black87 : Colors.grey.shade500,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (hasValue)
                  IconButton(
                    icon: Icon(Icons.clear, color: Colors.grey.shade500, size: 20),
                    onPressed: () {
                      setState(() {
                        _formValues[property.id] = null;
                      });
                    },
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
        ),
        if (property.isRequired && !hasValue)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'This field is required',
              style: TextStyle(
                color: Colors.red.shade600,
                fontSize: 12,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _submitForm() async {
    if (_selectedClass == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a class first'),
          backgroundColor: Colors.orange.shade600,
        ),
      );
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final service = context.read<MFilesService>();

    // Required file check for document objects
    String? uploadId;
    if (widget.objectType.isDocument) {
      if (_selectedFile == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Please select a file for document objects'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
      uploadId = await service.uploadFile(_selectedFile!);
      if (uploadId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('File upload failed'),
            backgroundColor: Colors.red.shade600,
          ),
        );
        return;
      }
    }

    // Map user inputs to PropertyValueRequest
    final List<PropertyValueRequest> properties = [];

    for (final prop in service.classProperties) {
      final value = _formValues[prop.id];

      // Skip null values for optional fields
      if (value == null && !prop.isRequired) continue;

      properties.add(PropertyValueRequest(
        propId: prop.id,
        value: value,
        propertyType: prop.propertyType,
      ));
    }

    // Ensure Name property is included
    final hasName = properties.any((p) => p.propId == 0);
    if (!hasName) {
      final objectName = _formValues[0] ?? 'Unnamed Object';
      properties.insert(0, PropertyValueRequest(
        propId: 0,
        value: objectName,
        propertyType: 'MFDatatypeText',
      ));
    }

    // Build the creation request
    final request = ObjectCreationRequest(
      objectID: 0,
      classID: _selectedClass!.id,
      properties: properties,
      vaultGuid: service.vaultGuid,
      userID: service.userId ?? 0, 
      uploadId: uploadId,
    );

    print('Submitting object creation: ${jsonEncode(request.toJson())}');

    final success = await service.createObject(request);

    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Object created successfully!'),
            backgroundColor: Colors.green.shade600,
          ),
        );
        Navigator.pop(context);
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create object: ${service.error}'),
            backgroundColor: Colors.red.shade600,
          ),
        );
      }
    }
  }

  Widget _buildFormField(ClassProperty property) {
    final decoration = InputDecoration(
      labelText: property.title,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
      ),
      filled: true,
      fillColor: Colors.grey.shade50,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 14,
      ),
    );

    switch (property.propertyType) {
      case 'MFDatatypeLookup':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(property.title, style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            )),
            const SizedBox(height: 8),
            LookupField(
              title: property.title,
              propertyId: property.id,
              isMultiSelect: false,
              onSelected: (selectedItems) {
                setState(() {
                  _formValues[property.id] = selectedItems.isNotEmpty 
                      ? selectedItems.first.id 
                      : null;
                });
              },
            ),
          ],
        );

      case 'MFDatatypeMultiSelectLookup':
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(property.title, style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            )),
            const SizedBox(height: 8),
            LookupField(
              title: property.title,
              propertyId: property.id,
              isMultiSelect: true,
              onSelected: (selectedItems) {
                setState(() {
                  _formValues[property.id] = selectedItems.map((i) => i.id).toList();
                });
              },
            ),
          ],
        );

      case 'MFDatatypeText':
        return TextFormField(
          decoration: decoration,
          validator: (value) {
            if (property.isRequired && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
          onChanged: (value) {
            setState(() {
              _formValues[property.id] = value;
            });
          },
        );

      case 'MFDatatypeInteger':
        return TextFormField(
          decoration: decoration,
          keyboardType: TextInputType.number,
          validator: (value) {
            if (property.isRequired && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
          onChanged: (value) {
            setState(() {
              _formValues[property.id] = int.tryParse(value);
            });
          },
        );

      case 'MFDatatypeMultiLineText':
        return TextFormField(
          decoration: decoration,
          maxLines: 4,
          validator: (value) {
            if (property.isRequired && (value == null || value.isEmpty)) {
              return 'This field is required';
            }
            return null;
          },
          onChanged: (value) {
            setState(() {
              _formValues[property.id] = value;
            });
          },
        );

      case 'MFDatatypeDate':
        return _buildDateField(property);

      case 'MFDatatypeTime':
        return _buildTimeField(property);

      case 'MFDatatypeBoolean':
        return Container(
          margin: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.circular(8),
            color: Colors.grey.shade50,
          ),
          child: CheckboxListTile(
            title: Text(
              property.title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.grey.shade700,
              ),
            ),
            subtitle: property.isRequired 
                ? Text(
                    'Required',
                    style: TextStyle(
                      color: Colors.red.shade600,
                      fontSize: 12,
                    ),
                  )
                : null,
            value: _formValues[property.id] ?? false,
            onChanged: (value) {
              setState(() {
                _formValues[property.id] = value ?? false;
              });
            },
            controlAffinity: ListTileControlAffinity.leading,
          ),
        );

      default:
        return TextFormField(
          decoration: decoration,
          onChanged: (value) {
            setState(() {
              _formValues[property.id] = value;
            });
          },
        );
    }
  }

  Widget _buildClassSelector() {
    return Consumer<MFilesService>(
      builder: (context, service, child) {
        if (_isLoadingClasses) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading classes...'),
                ],
              ),
            ),
          );
        }

        final objectClasses = service.objectClasses
            .where((cls) => cls.objectTypeId == widget.objectType.id)
            .toList();

        if (objectClasses.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.orange.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.info_outline, color: Colors.orange.shade700, size: 48),
                const SizedBox(height: 16),
                Text(
                  'No classes available for this object type',
                  style: TextStyle(color: Colors.orange.shade700),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          );
        }

        // Group classes
        final ungroupedClasses = objectClasses
            .where((cls) => !service.isClassInAnyGroup(cls.id))
            .toList();
        final classGroups = service.getClassGroupsForType(widget.objectType.id);

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.shade100,
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.folder_open,
                    color: const Color(0xFF0A1541),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Select Class',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the type of ${widget.objectType.displayName} to create',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 16),

              // Ungrouped classes
              if (ungroupedClasses.isNotEmpty) ...[
                const Padding(
                  padding: EdgeInsets.only(bottom: 8.0),
                  child: Text(
                    'General',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ),
                ...ungroupedClasses.map((cls) => _buildClassOption(cls)),
                const SizedBox(height: 8),
              ],

              // Grouped classes
              ...classGroups.map((group) => Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                        child: Text(
                          group.classGroupName,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                      ...group.members.map((cls) => _buildClassOption(cls)),
                    ],
                  )),
            ],
          ),
        );
      },
    );
  }

  Widget _buildClassOption(ObjectClass cls) {
    final isSelected = _selectedClass?.id == cls.id;

    return InkWell(
      onTap: () => _onClassSelected(cls),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF0A1541).withOpacity(0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? const Color(0xFF0A1541) : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? const Color(0xFF0A1541) : Colors.grey.shade400,
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                cls.displayName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? const Color(0xFF0A1541) : Colors.black87,
                  fontSize: 15,
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Color(0xFF0A1541),
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: AppBar(
            backgroundColor: const Color(0xFF0A1541),
            elevation: 0,
            titleSpacing: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Image.asset(
                      'assets/alignsyslogo.png',
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.0),
                  child: Text(
                    '|',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/TechEdgeLogo.png',
                      height: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        body: Consumer<MFilesService>(
          builder: (context, service, child) {
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Header Section
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        widget.objectType.isDocument ? Icons.description : Icons.folder,
                        color: const Color(0xFF0A1541),
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create ${widget.objectType.displayName}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _selectedClass != null 
                                  ? 'Class: ${_selectedClass!.displayName}'
                                  : 'Select a class to continue',
                              style: TextStyle(
                                color: Colors.grey.shade600,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // Class Selection Section
                _buildClassSelector(),
                const SizedBox(height: 16),

                // Only show the rest of the form if a class is selected
                if (_selectedClass != null) ...[
                  // File Upload Section (for document objects)
                  if (widget.objectType.isDocument) ...[
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade100,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.attach_file, color: Color(0xFF0A1541)),
                              const SizedBox(width: 8),
                              const Text(
                                'File Upload',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade200),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _selectedFileName ?? 'No file selected',
                                    style: TextStyle(
                                      color: _selectedFileName != null
                                          ? Colors.green.shade700
                                          : Colors.grey.shade600,
                                      fontWeight: _selectedFileName != null
                                          ? FontWeight.w500
                                          : FontWeight.normal,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  onPressed: _pickFile,
                                  icon: const Icon(Icons.folder_open, size: 18),
                                  label: const Text('Browse'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF0A1541),
                                    foregroundColor: Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
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

                  // Properties Section
                  if (service.isLoading && service.classProperties.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Loading properties...'),
                          ],
                        ),
                      ),
                    )
                  else if (service.classProperties.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.grey.shade200),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.shade100,
                            blurRadius: 4,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Form(
                        key: _formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.settings, color: Color(0xFF0A1541)),
                                const SizedBox(width: 8),
                                const Text(
                                  'Properties',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 16),
                            
                            // Property form fields
                            ...service.classProperties
                                .where((property) => !property.isHidden)
                                .map((property) => Padding(
                                      padding: const EdgeInsets.only(bottom: 16),
                                      child: _buildFormField(property),
                                    )),
                          ],
                        ),
                      ),
                    ),
                  
                  const SizedBox(height: 24),
                  
                  // Submit button
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
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A1541),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        elevation: 2,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 16),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}