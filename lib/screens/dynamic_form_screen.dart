import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mfiles_app/screens/property_form_field.dart';
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
    required this.objectClass,
  });

  final ObjectClass objectClass;
  final VaultObjectType objectType;

  @override
  State<DynamicFormScreen> createState() => _DynamicFormScreenState();
}

class _DynamicFormScreenState extends State<DynamicFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<int, dynamic> _formValues = {};
  File? _selectedFile;
  String? _selectedFileName;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MFilesService>().fetchClassProperties(
            widget.objectType.id,
            widget.objectClass.id,
          );
    });
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
      firstDate: DateTime(1800), // Extended back to 1800
      lastDate: DateTime(2200),  // Extended forward to 2200
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
      // For time-only, we'll use today's date as base
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
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Check for required date/time fields
    final service = context.read<MFilesService>();
    for (final property in service.classProperties) {
      final titleLower = property.title.toLowerCase();
      final isTimeField = property.propertyType == 'MFDatatypeTime' || 
                         property.propertyType == 'MFDatatypeTimestamp' ||
                         titleLower.contains('time');
      final isDateField = property.propertyType == 'MFDatatypeDate' ||
                         titleLower.contains('date');
      
      if (property.isRequired && 
          (isTimeField || isDateField) &&
          _formValues[property.id] == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${property.title} is required'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        return;
      }
      
      // Check for required text fields
      if (property.isRequired && 
          (property.propertyType == 'MFDatatypeText' || property.propertyType == 'MFDatatypeMultiLineText') &&
          (_formValues[property.id] == null || _formValues[property.id].toString().trim().isEmpty)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${property.title} is required'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        return;
      }
    }
    
    // Check if required file is selected for document objects
    if (widget.objectType.isDocument && _selectedFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Please select a file for document objects'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      return;
    }

    String? uploadId;
    
    // Upload file if document object
    if (widget.objectType.isDocument && _selectedFile != null) {
      uploadId = await service.uploadFile(_selectedFile!);
      if (uploadId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Failed to upload file'),
            backgroundColor: Colors.red.shade600,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
        return;
      }
    }

    // Prepare property values - USE ORIGINAL VALUES, NOT CONVERTED ONES
    final properties = <PropertyValueRequest>[];
    
    // First, ensure all required boolean fields have a value
    for (final property in service.classProperties) {
      if (property.propertyType == 'MFDatatypeBoolean' && !_formValues.containsKey(property.id)) {
        _formValues[property.id] = false; // Default to false if not set
        print('Setting default false for boolean field: ${property.title}');
      }
    }
    
    for (final entry in _formValues.entries) {
      final property = service.classProperties.firstWhere((p) => p.id == entry.key);

      // Debug print the original value
      print('Property ${entry.key} original value: ${entry.value} (${entry.value.runtimeType})');

      properties.add(PropertyValueRequest(
        propId: entry.key,
        value: entry.value, // ✅ Use the original value, let toJson() handle formatting
        propertyType: property.propertyType,
      ));
    }

    // 🔥 Ensure Object Name property (PropertyDef: 0) is present
    final hasObjectName = properties.any((p) => p.propId == 0);
    if (!hasObjectName) {
      // Use Car Title as name, or fallback to 'Unnamed Object'
      final objectName = _formValues[1120]?.toString() ?? 'Unnamed Object';
      properties.insert(0, PropertyValueRequest(
        propId: 0,
        value: objectName,
        propertyType: 'MFDatatypeText',
      ));
    }

    // Create object request
    final request = ObjectCreationRequest(
      objectTypeId: widget.objectType.id,
      classId: widget.objectClass.id,
      properties: properties,
      uploadId: uploadId,
    );

    // Debug print
    print('Submitting: ${json.encode(request.toJson())}');

    // Submit the request
    final success = await service.createObject(request);
    
    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Object created successfully!'),
          backgroundColor: Colors.green.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
      Navigator.pop(context);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to create object: ${service.error}'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
    }
  }

  Widget _buildFormField(ClassProperty property) {
    // Debug print to see what property types we're getting
    print('Property ${property.title} has type: ${property.propertyType}');
    print('Checking cases - MFDatatypeTimestamp match: ${property.propertyType == 'MFDatatypeTimestamp'}');
    
    // Common field decoration
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

    // Handle different property types
    switch (property.propertyType) {
      case 'MFDatatypeLookup': // For Driver (single select)
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

      case 'MFDatatypeMultiSelectLookup': // For Staff (multi-select)
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
              print('Boolean field ${property.title} set to: ${value ?? false}');
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
            actions: [
            ],
          ),
        ),
        body: Consumer<MFilesService>(
          builder: (context, service, child) {
            if (service.isLoading && service.classProperties.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (service.error != null && service.classProperties.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.red,
                      size: 64,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${service.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        service.clearError();
                        service.fetchClassProperties(
                          widget.objectType.id,
                          widget.objectClass.id,
                        );
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF0A1541),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            if (service.classProperties.isEmpty) {
              return const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Colors.grey,
                      size: 64,
                    ),
                    SizedBox(height: 16),
                    Text(
                      'No properties found for this class',
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  ],
                ),
              );
            }

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
                        color: Colors.blue,
                        size: 32,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Create ${widget.objectClass.displayName}',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Object Type: ${widget.objectType.displayName}',
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
                            const Icon(Icons.attach_file, color: Colors.blue),
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
                            const Icon(Icons.settings, color: Colors.blue),
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
            );
          },
        ),
      ),
    );
  }
}