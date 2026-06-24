// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/auto_suggest_dialog.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../widgets/lookup_field.dart';
import 'package:intl/intl.dart';
import '../theme/app_colors.dart';
import '../models/lookup_item.dart';
import '../models/vault_object_type.dart';
import '../models/quick_create_result.dart';
import 'dynamic_form_screen.dart';

class TemplateFormScreen extends StatefulWidget {
  final int classId;
  final String className;
  final int templateObjectId;
  final String templateTitle;
  final int objectTypeId;

  const TemplateFormScreen({
    super.key,
    required this.classId,
    required this.className,
    required this.templateObjectId,
    required this.templateTitle,
    required this.objectTypeId,
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
  final Map<int, int> _propTypeIds = {};
  final Map<int, bool> _propAllowAdding = {};
  final Map<int, bool> _propObjectTypeVL = {};

  final Map<int, bool?> _boolValues = {};

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
    final canEdit =
        prop['userPermission']?['editPermission'] as bool? ?? true;
    return isAutomatic || _systemPropIds.contains(id) || !canEdit;
  }

  bool _isVisible(Map<String, dynamic> prop) {
    return !(prop['isHidden'] as bool? ?? false);
  }

  /// Resolves the object/value-list type ID from a prop map, trying all known
  /// key variants that different endpoints may return.
  int _resolveTypeId(Map<String, dynamic> prop) {
    final id = (prop['propId'] as num?)?.toInt() ?? 0;

    // Primary: use pre-fetched map from fetchClassProperties
  if (id > 0 && _propTypeIds.containsKey(id)) {
    return _propTypeIds[id]!;
  }

  // Fallback: try all known key variants
    final raw = prop['typeID'] ??
        prop['TypeID'] ??
        prop['typeId'] ??
        prop['TypeId'] ??
        prop['objectType'] ??
        prop['ObjectType'] ??
        prop['valueList'] ??
        prop['ValueList'];
    if (raw == null) {
      debugPrint('⚠️ AutoSuggest: no typeID-like key on this prop. '
          'Available keys: ${prop.keys.toList()}');
      return 0;
    }
    return raw is int
        ? raw
        : (raw is num ? raw.toInt() : int.tryParse('$raw') ?? 0);
  }

  /// Resolves whether the current user may add new items to this lookup's
  /// target, trying the raw prop map first (in case the template-props
  /// endpoint ever starts returning it directly) and falling back to the
  /// ClassProps-derived map. Defaults to false — if we can't confirm
  /// permission, we don't show the "+" button.
  bool _resolveAllowAdding(Map<String, dynamic> prop) {
    if (prop.containsKey('allowAdding')) {
      return prop['allowAdding'] as bool? ?? false;
    }
    final id = (prop['propId'] as num?)?.toInt() ?? 0;
    return _propAllowAdding[id] ?? false;
  }

  /// Resolves whether this lookup points at an M-Files object type (true)
  /// or a plain value list (false). See [_resolveAllowAdding] for the
  /// same fallback pattern.
  bool _resolveObjectTypeVL(Map<String, dynamic> prop) {
    if (prop.containsKey('objectTypeVL')) {
      return prop['objectTypeVL'] as bool? ?? false;
    }
    final id = (prop['propId'] as num?)?.toInt() ?? 0;
    return _propObjectTypeVL[id] ?? false;
  }

  Future<void> _loadProps() async {
    final service = context.read<MFilesService>();
    final vaultGuid = service.selectedVault?.guid ?? '';
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await service.fetchClassTemplateProps(
        vaultGuid: vaultGuid,
        classId: widget.classId,
        objectId: widget.templateObjectId,
        userId: service.currentUserId,
      );

      // ── Fetch class properties separately just to resolve typeId per propId ──
    // fetchClassTemplateProps doesn't return typeID; fetchClassProperties does.
    try {
      await service.fetchClassProperties(
        widget.objectTypeId,
        widget.classId,
      );
      for (final cp in service.classProperties) {
        if (cp.id > 0 && cp.typeId > 0) {
          _propTypeIds[cp.id] = cp.typeId;
        }
        if (cp.id > 0) {
          _propAllowAdding[cp.id] = cp.allowAdding;
          _propObjectTypeVL[cp.id] = cp.objectTypeVL;
        }
      }
      debugPrint('🔑 Resolved typeIds: $_propTypeIds');
    } catch (e) {
      debugPrint('⚠️ Could not resolve typeIds from class props: $e');
    }

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
              text: value.isNotEmpty &&
                      int.tryParse(value.split('.').first) != null
                  ? value.split('.').first
                  : '',
            );
            break;
          case 'MFDatatypeFloating':
            _controllers[id] = TextEditingController(
              text: value.isNotEmpty && double.tryParse(value) != null
                  ? value
                  : '',
            );
            break;
          case 'MFDatatypeDate':
            _values[id] = _normaliseDateValue(value);
            break;
          case 'MFDatatypeLookup':
          case 'MFDatatypeMultiSelectLookup':
            _values[id] = null;
            break;
          case 'MFDatatypeBoolean':
            _boolValues[id] = null;
            break;
          default:
            _controllers[id] = TextEditingController(text: value);
            break;
        }
      }

      setState(() {
        _props = data;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  String? _normaliseDateValue(String raw) {
    if (raw.isEmpty) return null;
    if (RegExp(r'^\d{4}-\d{2}-\d{2}').hasMatch(raw)) {
      return raw.substring(0, 10);
    }
    try {
      final parts = raw.split('/');
      if (parts.length == 3) {
        final m = int.parse(parts[0]);
        final d = int.parse(parts[1]);
        final y = int.parse(parts[2].split(' ')[0]);
        return '${y.toString().padLeft(4, '0')}-'
            '${m.toString().padLeft(2, '0')}-'
            '${d.toString().padLeft(2, '0')}';
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> _buildPropEntry({
    required int id,
    required String type,
    required dynamic rawValue,
    required bool isRequired,
    required Map<String, dynamic> prop,
  }) {
    String stringValue;

    switch (type) {
      case 'MFDatatypeInteger':
        stringValue = (int.tryParse(rawValue.toString()) ?? 0).toString();
        break;
      case 'MFDatatypeFloating':
        final d = double.tryParse(rawValue.toString()) ?? 0.0;
        stringValue = d.toString().contains('.') ? d.toString() : '$d.0';
        break;
      case 'MFDatatypeDate':
        stringValue = rawValue.toString();
        break;
      case 'MFDatatypeLookup':
        final intId = rawValue is int
            ? rawValue
            : int.tryParse(rawValue.toString()) ?? 0;
        stringValue = intId.toString();
        break;
      case 'MFDatatypeMultiSelectLookup':
        if (rawValue is List) {
          stringValue = rawValue
              .map((e) => e is int ? e : int.tryParse('$e') ?? 0)
              .join(',');
        } else {
          stringValue = rawValue.toString();
        }
        break;
      case 'MFDatatypeBoolean':
        if (rawValue is bool) {
          stringValue = rawValue.toString();
        } else {
          final s = rawValue.toString().toLowerCase().trim();
          stringValue =
              (s == 'true' || s == 'yes' || s == '1') ? 'true' : 'false';
        }
        break;
      default:
        stringValue = rawValue.toString();
    }

    return {
      'propId': id,
      'propertytype': type,
      'value': stringValue,
      'isRequired': isRequired,
      'isHidden': prop['isHidden'] ?? false,
      'isAutomatic': prop['isAutomatic'] ?? false,
      'title': prop['title'] ?? '',
    };
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
      } else if (type == 'MFDatatypeBoolean') {
        isEmpty = _boolValues[id] == null;
      } else {
        isEmpty = val == null || val.toString().trim().isEmpty;
      }
      if (isEmpty) {
        _showSnack('Required field "${prop['title']}" is missing',
            isError: true);
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
        final isRequired = prop['isRequired'] as bool? ?? false;

        if (_isReadOnly(prop)) continue;

        dynamic rawValue;

        if (type == 'MFDatatypeText' ||
            type == 'MFDatatypeMultiLineText' ||
            type == 'MFDatatypeInteger' ||
            type == 'MFDatatypeFloating') {
          rawValue = _controllers[id]?.text.trim() ?? '';
          if ((rawValue as String).isEmpty && !isRequired) continue;
        } else if (type == 'MFDatatypeLookup') {
          rawValue = _values[id];
          if (rawValue == null) {
            if (!isRequired) continue;
            rawValue = 0;
          }
        } else if (type == 'MFDatatypeMultiSelectLookup') {
          rawValue = _values[id];
          if (rawValue == null ||
              (rawValue is List && rawValue.isEmpty)) {
            if (!isRequired) continue;
            rawValue = <int>[];
          }
        } else if (type == 'MFDatatypeDate') {
          rawValue = _values[id] ?? '';
          if ((rawValue as String).isEmpty && !isRequired) continue;
        } else if (type == 'MFDatatypeBoolean') {
          final bv = _boolValues[id];
          if (bv == null && !isRequired) continue;
          rawValue = bv ?? false;
        } else {
          rawValue = _values[id] ?? _controllers[id]?.text ?? '';
          if (rawValue.toString().isEmpty && !isRequired) continue;
        }

        propsPayload.add(_buildPropEntry(
          id: id,
          type: type,
          rawValue: rawValue,
          isRequired: isRequired,
          prop: prop,
        ));
      }

      if (kDebugMode) {
        debugPrint('📤 Template payload props:');
        for (final p in propsPayload) {
          debugPrint(
              '   ${p['title']}(${p['propertytype']}) = '
              '${p['value']} [${p['value'].runtimeType}]');
        }
      }

      final payload = {
        'VaultGuid': vaultGuid,
        'ClassID': widget.classId,
        'ObjectId': widget.templateObjectId,
        'UserID': service.currentUserId,
        'Properties': propsPayload,
        'mfilesCreate': true,
      };

      await service.createObjectFromTemplate(payload);
      if (mounted) {
        unawaited(service.fetchRecentObjects());
        _showSnack('Created successfully from template!');
        Navigator.pop(context, true);
      }
    } catch (e) {
      setState(() => _submitting = false);
      if (mounted) _showSnack('Error: $e', isError: true);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        Icon(
            isError
                ? Icons.error_outline
                : Icons.check_circle_outline,
            color: Colors.white,
            size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text(message)),
      ]),
      backgroundColor:
          isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
      duration: Duration(seconds: isError ? 4 : 2),
    ));
  }

  Future<void> _pickDate(int propId) async {
    final existing = _values[propId];
    DateTime initial;
    try {
      initial = existing != null && existing.toString().isNotEmpty
          ? _apiDateFmt.parse(existing.toString())
          : DateTime.now();
    } catch (_) {
      initial = DateTime.now();
    }
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: DateTime(2200),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
            colorScheme: Theme.of(ctx)
                .colorScheme
                .copyWith(primary: _primaryBlue)),
        child: child!,
      ),
    );
    if (date != null) {
      setState(() => _values[propId] = _apiDateFmt.format(date));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.templateTitle,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w600)),
              Text(widget.className,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.white70)),
            ]),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _buildError()
              : _buildForm(),
    );
  }

  Widget _buildForm() {
    final editableProps =
        _props.where((p) => _isVisible(p) && !_isReadOnly(p)).toList();
    if (editableProps.isEmpty) {
      return Center(
          child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.info_outline,
                    size: 40, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                Text('No editable fields for this template.',
                    style: TextStyle(
                        fontSize: 15, color: Colors.grey.shade600),
                    textAlign: TextAlign.center),
              ])));
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      keyboardDismissBehavior:
          ScrollViewKeyboardDismissBehavior.onDrag,
      children: [
        _sectionHeader('Fill in Details',
            subtitle:
                'These fields will be reflected in the document.'),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE7EAF0)),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 14,
                  offset: const Offset(0, 6))
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            children: List.generate(editableProps.length * 2 - 1,
                (i) {
              if (i.isOdd) {
                return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                        height: 1,
                        thickness: 1,
                        color: Color(0xFFE2E8F0)));
              }
              return _buildEditableField(editableProps[i ~/ 2]);
            }),
          ),
        ),
        const SizedBox(height: 28),
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton.icon(
            onPressed: _submitting ? null : _submit,
            icon: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white)))
                : const Icon(Icons.check_circle_rounded, size: 20),
            label: Text(
                _submitting
                    ? 'Creating...'
                    : 'Create from Template',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.w700)),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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

    // CHANGED: use _resolveTypeId for resilient key lookup with diagnostics
    final typeId = _resolveTypeId(prop);
    final allowAdding = _resolveAllowAdding(prop);
    final objectTypeVL = _resolveObjectTypeVL(prop);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: RichText(
                text: TextSpan(
              text: title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF475569)),
              children: required
                  ? const [
                      TextSpan(
                          text: ' *',
                          style: TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.w800))
                    ]
                  : [],
            )),
          ),
          _buildInputForType(
              id, type, title, required, typeId, allowAdding, objectTypeVL),
        ]);
  }

  Widget _buildInputForType(int id, String type, String label, bool required,
      int typeId, bool allowAdding, bool objectTypeVL) {
    switch (type) {
      case 'MFDatatypeText':
      case 'MFDatatypeMultiLineText':
        final ctrl =
            _controllers.putIfAbsent(id, () => TextEditingController());
        return TextField(
          controller: ctrl,
          maxLines: type == 'MFDatatypeMultiLineText' ? 4 : 1,
          onChanged: (_) => setState(() {}),
          decoration: _textDeco(
              hint: 'Enter ${label.toLowerCase()}...',
              filled: ctrl.text.trim().isNotEmpty),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827)),
        );

      case 'MFDatatypeInteger':
        final ctrl =
            _controllers.putIfAbsent(id, () => TextEditingController());
        return TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          onChanged: (_) => setState(() {}),
          decoration: _textDeco(
              hint: 'Enter number...',
              filled: ctrl.text.trim().isNotEmpty),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827)),
        );

      case 'MFDatatypeFloating':
        final ctrl =
            _controllers.putIfAbsent(id, () => TextEditingController());
        return TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          onChanged: (_) => setState(() {}),
          decoration: _textDeco(
              hint: 'Enter amount...',
              filled: ctrl.text.trim().isNotEmpty),
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Color(0xFF111827)),
        );

      case 'MFDatatypeDate':
        final val = _values[id];
        final has = val != null && val.toString().isNotEmpty;
        String display = 'Tap to select date';
        if (has) {
          try {
            display =
                _uiDateFmt.format(_apiDateFmt.parse(val.toString()));
          } catch (_) {
            display = val.toString();
          }
        }
        return GestureDetector(
          onTap: () => _pickDate(id),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 13),
            decoration: BoxDecoration(
              color: has ? _filledFill : AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: has ? _filledBorder : Colors.grey.shade200,
                  width: has ? 1.5 : 1),
            ),
            child: Row(children: [
              Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                      color: has
                          ? _primaryBlue.withOpacity(0.1)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6)),
                  child: Icon(Icons.calendar_today_rounded,
                      size: 16,
                      color: has ? _primaryBlue : Colors.grey.shade400)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text(display,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              has ? FontWeight.w500 : FontWeight.w400,
                          color: has
                              ? const Color(0xFF111827)
                              : Colors.grey.shade400))),
              has
                  ? const Icon(Icons.check_circle_rounded,
                      color: _filledBorder, size: 18)
                  : Icon(Icons.keyboard_arrow_down,
                      color: Colors.grey.shade400, size: 20),
            ]),
          ),
        );

      case 'MFDatatypeBoolean':
        final bv = _boolValues[id];
        return _buildBooleanField(id, bv, required);

      case 'MFDatatypeLookup':
        final hasValue = _values[id] != null;
        return _lookupShell(
          label: label,
          required: required,
          hasValue: hasValue,
          isSingleSelect: true,
          onCreateNew: _resolveLookupCreateCallback(
            propId: id,
            label: label,
            typeId: typeId,
            allowAdding: allowAdding,
            objectTypeVL: objectTypeVL,
            isMulti: false,
          ),
          field: LookupField(
            title: label,
            propertyId: id,
            isMultiSelect: false,
            preSelectedIds: hasValue ? [_values[id] as int] : [],
            injectedItems: (_selectedLookupItems[id])?.cast<LookupItem>(),
            onSelected: (items) {
              setState(() {
                if (items.isNotEmpty) {
                  _values[id] = items.first.id;
                  _selectedLookupItems[id] = items;
                } else {
                  _values[id] = null;
                  _selectedLookupItems.remove(id);
                }
              });
              if (items.isNotEmpty) {
                _triggerAutoSuggest(
                  selectedObjectId: items.first.id,
                  selectedObjectTypeId: typeId,
                  displayLabel: items.first.displayValue,
                );
              }
            },
          ),
        );

      case 'MFDatatypeMultiSelectLookup':
        final selectedItems = _selectedLookupItems[id] ?? [];
        final selectedIds = (_values[id] is List)
            ? (_values[id] as List).cast<int>()
            : <int>[];
        return _lookupShell(
          label: label,
          required: required,
          hasValue: selectedIds.isNotEmpty,
          selectedTexts: selectedItems
              .map((e) => e.displayValue.toString())
              .toList(),
          selectedItems: selectedItems,
          propertyId: id,
          onCreateNew: _resolveLookupCreateCallback(
            propId: id,
            label: label,
            typeId: typeId,
            allowAdding: allowAdding,
            objectTypeVL: objectTypeVL,
            isMulti: true,
          ),
          field: LookupField(
            key: ValueKey(selectedIds.join(',')),
            title: label,
            propertyId: id,
            isMultiSelect: true,
            preSelectedIds: selectedIds,
            injectedItems: selectedItems.cast<LookupItem>(),
            onSelected: (items) {
              setState(() {
                _values[id] = items.map((i) => i.id).toList();
                _selectedLookupItems[id] = items;
              });
              if (items.isNotEmpty) {
                _triggerAutoSuggest(
                  selectedObjectId: items.first.id,
                  selectedObjectTypeId: typeId,
                  displayLabel: items.first.displayValue,
                );
              }
            },
          ),
        );

      default:
        final ctrl =
            _controllers.putIfAbsent(id, () => TextEditingController());
        return TextField(
          controller: ctrl,
          onChanged: (_) => setState(() {}),
          decoration: _textDeco(
              hint: 'Enter value...',
              filled: ctrl.text.trim().isNotEmpty),
          style: const TextStyle(
              fontSize: 14, color: Color(0xFF111827)),
        );
    }
  }

  Widget _buildBooleanField(int id, bool? current, bool required) {
    Widget pill(String label, bool value) {
      final selected = current == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() => _boolValues[id] = value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            margin: const EdgeInsets.all(4),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: selected ? _primaryBlue : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade600,
              ),
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          pill('Yes', true),
          Container(width: 1, height: 36, color: Colors.grey.shade200),
          pill('No', false),
        ],
      ),
    );
  }

  InputDecoration _textDeco(
      {required String hint, required bool filled}) {
    return InputDecoration(
      hintText: hint,
      hintStyle:
          TextStyle(color: Colors.grey.shade400, fontSize: 13),
      filled: true,
      fillColor: filled ? _filledFill : AppColors.surfaceLight,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(
              color: filled ? _filledBorder : Colors.grey.shade200,
              width: filled ? 1.5 : 1)),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: Colors.grey.shade200)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide:
              const BorderSide(color: _primaryBlue, width: 2)),
      suffixIcon: filled
          ? const Icon(Icons.check_circle_rounded,
              color: _filledBorder, size: 18)
          : null,
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
    final showMulti =
        selectedTexts != null && selectedTexts.isNotEmpty;
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  decoration: BoxDecoration(
                    color:
                        hasValue ? _filledFill : AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: hasValue
                            ? _filledBorder
                            : Colors.grey.shade200,
                        width: hasValue ? 1.5 : 1),
                  ),
                  child: Row(children: [
                    Expanded(
                        child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12),
                            child: field)),
                    if (hasValue)
                      const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: Icon(Icons.check_circle_rounded,
                              color: _filledBorder, size: 18)),
                  ]),
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
                children:
                    List.generate(selectedTexts.length, (index) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: const Color(0xFFBFDBFE))),
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: Text(
                              selectedTexts[index],
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFF1E40AF)),
                            ),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () {
                              if (propertyId == null ||
                                  selectedItems == null) return;
                              setState(() {
                                final newItems =
                                    List<dynamic>.from(selectedItems)
                                      ..removeAt(index);
                                _selectedLookupItems[propertyId] =
                                    newItems;
                                _values[propertyId] =
                                    newItems.map((i) => i.id).toList();
                              });
                            },
                            child: Container(
                                width: 16,
                                height: 16,
                                decoration: BoxDecoration(
                                    color: const Color(0xFF3B82F6)
                                        .withOpacity(0.2),
                                    shape: BoxShape.circle),
                                child: const Icon(Icons.close,
                                    size: 10,
                                    color: Color(0xFF1E40AF))),
                          ),
                        ]),
                  );
                })),
          ],
          if (required && !hasValue)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(children: [
                Icon(Icons.error_outline,
                    size: 14, color: Colors.red.shade600),
                const SizedBox(width: 4),
                Text('This field is required',
                    style: TextStyle(
                        color: Colors.red.shade600, fontSize: 12))
              ]),
            ),
        ]);
  }

  /// The blue "+" button rendered next to lookup fields, matching the web
  /// app's inline quick-create affordance.
  Widget _quickCreateButton(VoidCallback onTap) {
    return Material(
      color: _primaryBlue,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: const SizedBox(
          width: 48,
          height: 48,
          child: Icon(Icons.add, color: Colors.white, size: 22),
        ),
      ),
    );
  }

  Widget _sectionHeader(String title, {String? subtitle}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF0F172A))),
      if (subtitle != null) ...[
        const SizedBox(height: 3),
        Text(subtitle,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: Color(0xFF64748B)))
      ],
    ]);
  }

  Widget _buildError() {
    return Center(
        child: Padding(
            padding: const EdgeInsets.all(32),
            child:
                Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.error_outline_rounded,
                  size: 48, color: Colors.red.shade400),
              const SizedBox(height: 16),
              const Text('Failed to load template',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(_error!,
                  style: TextStyle(
                      fontSize: 13, color: Colors.grey.shade600),
                  textAlign: TextAlign.center),
              const SizedBox(height: 20),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryBlue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10))),
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _loadProps();
                },
                child: const Text('Retry'),
              ),
            ])));
  }

  // ── QUICK CREATE (inline "+" button on lookup fields) ──────────────────────

  /// Decides which inline "+" action (if any) applies to a lookup property:
  /// - null: user lacks permission to add (allowAdding == false)
  /// - full quick-create screen: the lookup targets an M-Files object type
  /// - lightweight add-value dialog: the lookup targets a plain value list
  VoidCallback? _resolveLookupCreateCallback({
    required int propId,
    required String label,
    required int typeId,
    required bool allowAdding,
    required bool objectTypeVL,
    required bool isMulti,
  }) {
    if (!allowAdding) return null;
    if (objectTypeVL) {
      return () => _handleQuickCreate(
            propId: propId,
            label: label,
            typeId: typeId,
            isMulti: isMulti,
          );
    }
    return () => _handleAddValueListItem(
          propId: propId,
          label: label,
          typeId: typeId,
          isMulti: isMulti,
        );
  }

  /// Pushes a [DynamicFormScreen] scoped to [typeId] so the user can create
  /// a related object without leaving this template form.
  Future<void> _handleQuickCreate({
    required int propId,
    required String label,
    required int typeId,
    required bool isMulti,
  }) async {
    final service = context.read<MFilesService>();

    if (typeId <= 0) {
      _showSnack(
        'Cannot create a new $label: target type unknown',
        isError: true,
      );
      return;
    }

    final targetType = service.objectTypes.firstWhere(
      (t) => t.id == typeId,
      orElse: () => VaultObjectType(
        id: typeId,
        displayName: label,
        isDocument: false,
        name: label,
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
      _showSnack('$label created — please select it from the search list');
      return;
    }

    final newItem =
        LookupItem(id: result.objectId!, displayValue: result.displayValue);

    setState(() {
      if (isMulti) {
        final existing = List<LookupItem>.from(
            (_selectedLookupItems[propId] ?? const []).cast<LookupItem>());
        if (!existing.any((i) => i.id == newItem.id)) {
          existing.add(newItem);
        }
        _selectedLookupItems[propId] = existing;
        _values[propId] = existing.map((i) => i.id).toList();
      } else {
        _selectedLookupItems[propId] = [newItem];
        _values[propId] = newItem.id;
      }
    });

    _showSnack('$label created and selected');

    _triggerAutoSuggest(
      selectedObjectId: newItem.id,
      selectedObjectTypeId: typeId,
      displayLabel: newItem.displayValue,
    );
  }

  /// Opens a lightweight "add a value" dialog for lookups that point at a
  /// plain value list (not an M-Files object type) — just a name, no class
  /// or metadata, posted straight to AddValuelistItem.
  Future<void> _handleAddValueListItem({
    required int propId,
    required String label,
    required int typeId,
    required bool isMulti,
  }) async {
    if (typeId <= 0) {
      _showSnack(
        'Cannot add a new $label: value list unknown',
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
                'Add new $label',
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
                  hintText: 'Enter ${label.toLowerCase()}',
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
      valueListId: typeId,
      name: name,
    );

    if (!mounted) return;

    if (newItem == null) {
      _showSnack('Failed to add value: ${service.error ?? "unknown error"}',
          isError: true);
      return;
    }

    setState(() {
      if (isMulti) {
        final existing = List<LookupItem>.from(
            (_selectedLookupItems[propId] ?? const []).cast<LookupItem>());
        if (!existing.any((i) => i.id == newItem.id)) {
          existing.add(newItem);
        }
        _selectedLookupItems[propId] = existing;
        _values[propId] = existing.map((i) => i.id).toList();
      } else {
        _selectedLookupItems[propId] = [newItem];
        _values[propId] = newItem.id;
      }
    });

    _showSnack('$label value added and selected');
  }

  Future<void> _triggerAutoSuggest({
    required int selectedObjectId,
    required int selectedObjectTypeId,
    required String displayLabel,
  }) async {
    debugPrint('🔍 AutoSuggest: objectId=$selectedObjectId typeId=$selectedObjectTypeId');

    // ADDED: warn early if typeId resolved to 0 so we know to check the log
    // above for the "no typeID-like key" diagnostic from _resolveTypeId.
    if (selectedObjectTypeId == 0) {
      debugPrint('⚠️ AutoSuggest: selectedObjectTypeId resolved to 0 — '
          'GetObjectViewProps will likely return nothing usable. Check the '
          '"no typeID-like key" log above for the real keys on this prop.');
    }

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

    final formPropIds = _props
        .where((p) =>
            !(p['isHidden'] as bool? ?? false) &&
            !(p['isAutomatic'] as bool? ?? false))
        .map((p) => (p['propId'] as num?)?.toInt() ?? 0)
        .where((id) => id > 0)
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
          _values[f.propertyId] = ids;
          final names = f.displayValue.split(', ');
          _selectedLookupItems[f.propertyId] = List.generate(
            ids.length,
            (i) => LookupItem(
              id: ids[i],
              displayValue: i < names.length ? names[i] : ids[i].toString(),
            ),
          );
        } else if (type.contains('lookup')) {
          _values[f.propertyId] = f.rawValue as int;
          _selectedLookupItems[f.propertyId] = [
            LookupItem(id: f.rawValue as int, displayValue: f.displayValue),
          ];
        } else if (type.contains('text') ||
            type.contains('integer') ||
            type.contains('float')) {
          _controllers[f.propertyId]?.text = f.rawValue.toString();
        } else if (type.contains('boolean')) {
          _boolValues[f.propertyId] = f.rawValue as bool?;
        } else if (type.contains('date')) {
          _values[f.propertyId] = f.rawValue;
        } else {
          _values[f.propertyId] = f.rawValue;
        }
      }
    });
  }
}