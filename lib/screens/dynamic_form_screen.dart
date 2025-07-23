import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/property_form_field.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../services/mfiles_service.dart';
import '../models/vault_object_type.dart';
import '../models/object_class.dart';
import '../models/class_property.dart';
import '../models/object_creation_request.dart';

class DynamicFormScreen extends StatefulWidget {
  final VaultObjectType objectType;
  final ObjectClass objectClass;

  const DynamicFormScreen({
    super.key,
    required this.objectType,
    required this.objectClass,
  });

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

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final service = context.read<MFilesService>();
    
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

    // Prepare property values
    final properties = <PropertyValueRequest>[];
    for (final entry in _formValues.entries) {
      final property = service.classProperties.firstWhere((p) => p.id == entry.key);

      // Debug print to check type
      print('Property ${entry.key} value type: ${entry.value.runtimeType}');

      properties.add(PropertyValueRequest(
        propId: entry.key,
        value: entry.value,
        propertytype: property.propertyType,
      ));
    }

    // 🔥 Ensure Object Name property (PropertyDef: 0) is present
    final hasObjectName = properties.any((p) => p.propId == 0);
    if (!hasObjectName) {
      // Try to find a suitable name value from your form (first non-empty text field)
      final nameEntry = _formValues.entries.firstWhere(
        (e) => e.value != null && e.value.toString().trim().isNotEmpty,
        orElse: () => const MapEntry(0, 'Unnamed Object'),
      );
      properties.insert(
        0,
        PropertyValueRequest(
          propId: 0,
          value: nameEntry.value,
          propertytype: 'MFDatatypeText', // MFDatatypeText
        ),
      );
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
                      'assets/mfileslogo.png',
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
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: OutlinedButton.icon(
                  onPressed: () => _submitForm(),
                  icon: const Icon(Icons.save, color: Colors.white, size: 20),
                  label: const Text(
                    'Save',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A1541),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
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
                                  child: PropertyFormField(
                                    property: property,
                                    onChanged: (value) {
                                      setState(() {
                                        _formValues[property.id] = value;
                                      });
                                    },
                                  ),
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