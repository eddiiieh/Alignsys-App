// ignore_for_file: constant_pattern_never_matches_value_type

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/class_property.dart';
import '../widgets/lookup_field.dart';
import '../models/object_creation_request.dart';
import '../services/mfiles_service.dart';


class PropertyFormField extends StatefulWidget {
  final ClassProperty property;
  final Function(dynamic) onChanged;

  const PropertyFormField({
    super.key,
    required this.property,
    required this.onChanged,
  });

  @override
  State<PropertyFormField> createState() => _PropertyFormFieldState();
}

class _PropertyFormFieldState extends State<PropertyFormField> {
  late TextEditingController _controller;
  DateTime? _selectedDate;
  DateTime? _selectedDateTime;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDateForMFiles(DateTime date) {
    // M-Files expects date in format: YYYY-MM-DDTHH:MM:SS.000Z or YYYY-MM-DD
    // For date only (DataType 5), use: YYYY-MM-DD
    return DateFormat('yyyy-MM-dd').format(date);
  }

  String _formatDateTimeForMFiles(DateTime dateTime) {
    // M-Files expects datetime in format: YYYY-MM-DDTHH:MM:SS.000Z
    // Try this format first, if it doesn't work, we'll use ISO 8601
    return DateFormat("yyyy-MM-dd'T'HH:mm:ss.000'Z'").format(dateTime.toUtc());
  }

  Future<void> _selectDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    
    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _controller.text = DateFormat('MMM dd, yyyy').format(picked);
      });
      // Send the M-Files formatted date
      widget.onChanged(_formatDateForMFiles(picked));
    }
  }

  Future<void> _selectDateTime() async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDateTime ?? DateTime.now(),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    
    if (pickedDate != null) {
      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(_selectedDateTime ?? DateTime.now()),
      );
      
      if (pickedTime != null) {
        final DateTime combined = DateTime(
          pickedDate.year,
          pickedDate.month,
          pickedDate.day,
          pickedTime.hour,
          pickedTime.minute,
        );
        
        setState(() {
          _selectedDateTime = combined;
          _controller.text = DateFormat('MMM dd, yyyy HH:mm').format(combined);
        });
        // Send the M-Files formatted datetime
        widget.onChanged(_formatDateTimeForMFiles(combined));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.property.propertyType) {
      case 1: // MFDatatypeText
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.property.displayName,
            hintText: 'Enter ${widget.property.displayName.toLowerCase()}',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          validator: widget.property.isRequired
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '${widget.property.displayName} is required';
                  }
                  return null;
                }
              : null,
          onChanged: (value) {
            widget.onChanged(value.trim().isEmpty ? null : value.trim());
          },
        );

      case 2: // MFDatatypeInteger
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.property.displayName,
            hintText: 'Enter ${widget.property.displayName.toLowerCase()}',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          keyboardType: TextInputType.number,
          validator: widget.property.isRequired
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '${widget.property.displayName} is required';
                  }
                  if (int.tryParse(value.trim()) == null) {
                    return 'Please enter a valid number';
                  }
                  return null;
                }
              : (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    if (int.tryParse(value.trim()) == null) {
                      return 'Please enter a valid number';
                    }
                  }
                  return null;
                },
          onChanged: (value) {
            final trimmed = value.trim();
            if (trimmed.isEmpty) {
              widget.onChanged(null);
            } else {
              final parsed = int.tryParse(trimmed);
              widget.onChanged(parsed);
            }
          },
        );

      case 3: // MFDatatypeFloating
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.property.displayName,
            hintText: 'Enter ${widget.property.displayName.toLowerCase()}',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          validator: widget.property.isRequired
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '${widget.property.displayName} is required';
                  }
                  if (double.tryParse(value.trim()) == null) {
                    return 'Please enter a valid decimal number';
                  }
                  return null;
                }
              : (value) {
                  if (value != null && value.trim().isNotEmpty) {
                    if (double.tryParse(value.trim()) == null) {
                      return 'Please enter a valid decimal number';
                    }
                  }
                  return null;
                },
          onChanged: (value) {
            final trimmed = value.trim();
            if (trimmed.isEmpty) {
              widget.onChanged(null);
            } else {
              final parsed = double.tryParse(trimmed);
              widget.onChanged(parsed);
            }
          },
        );

      case 5: // MFDatatypeDate
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.property.displayName,
            hintText: 'Select ${widget.property.displayName.toLowerCase()}',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: const Icon(Icons.calendar_today),
          ),
          readOnly: true,
          validator: widget.property.isRequired
              ? (value) {
                  if (_selectedDate == null) {
                    return '${widget.property.displayName} is required';
                  }
                  return null;
                }
              : null,
          onTap: _selectDate,
        );

      case 7: // MFDatatypeTimestamp
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.property.displayName,
            hintText: 'Select ${widget.property.displayName.toLowerCase()}',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
            suffixIcon: const Icon(Icons.access_time),
          ),
          readOnly: true,
          validator: widget.property.isRequired
              ? (value) {
                  if (_selectedDateTime == null) {
                    return '${widget.property.displayName} is required';
                  }
                  return null;
                }
              : null,
          onTap: _selectDateTime,
        );

      case 8: // MFDatatypeBoolean
        return FormField<bool>(
          initialValue: false,
          validator: widget.property.isRequired
              ? (value) {
                  // For boolean fields, we might want to ensure they're explicitly set
                  return null; // Usually booleans don't need validation
                }
              : null,
          builder: (FormFieldState<bool> state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Checkbox(
                      value: state.value ?? false,
                      onChanged: (bool? value) {
                        state.didChange(value ?? false);
                        widget.onChanged(value ?? false);
                      },
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.property.displayName,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                if (state.hasError)
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Text(
                      state.errorText!,
                      style: const TextStyle(color: Colors.red, fontSize: 12),
                    ),
                  ),
              ],
            );
          },
        );

      case 9: // MFDatatypeMultiSelectLookup
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.property.displayName, // Use widget.property.displayName instead of property.title
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          LookupField(
            title: widget.property.displayName,
            propertyId: widget.property.id,
            isMultiSelect: true, // Multi-select for MFDatatypeMultiSelectLookup
            onSelected: (selectedItems) {
              widget.onChanged(selectedItems.map((i) => i.id).toList()); // Use widget.onChanged
            },
          ),
        ],
      );
      case 10: // MFDatatypeLookup
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.property.displayName, // Use widget.property.displayName instead of property.title
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          LookupField(
            title: widget.property.displayName,
            propertyId: widget.property.id,
            isMultiSelect: false, // Single select for MFDatatypeLookup
            onSelected: (selectedItems) {
              widget.onChanged(selectedItems.isNotEmpty ? selectedItems.first.id : null); // Use widget.onChanged
            },
          ),
        ],
      );
        // For lookups, you'd typically need to fetch the available options
        // and display them in a dropdown. For now, treating as text input
      case 11: // MFDatatypeMultiLineText
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: widget.property.displayName,
            hintText: 'Enter ${widget.property.displayName.toLowerCase()}',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          maxLines: 4,
          validator: widget.property.isRequired
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '${widget.property.displayName} is required';
                  }
                  return null;
                }
              : null,
          onChanged: (value) {
            widget.onChanged(value.trim().isEmpty ? null : value.trim());
          },
        );

      default:
        return TextFormField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: '${widget.property.displayName} (Type: ${widget.property.propertyType})',
            hintText: 'Enter value',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
          validator: widget.property.isRequired
              ? (value) {
                  if (value == null || value.trim().isEmpty) {
                    return '${widget.property.displayName} is required';
                  }
                  return null;
                }
              : null,
          onChanged: (value) {
            widget.onChanged(value.trim().isEmpty ? null : value.trim());
          },
        );
    }
  }
}