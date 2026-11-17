import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/lookup_item.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import '../theme/app_colors.dart';

class LookupField extends StatefulWidget {
  final String title;
  final int propertyId;
  final bool isMultiSelect;
  final Function(List<LookupItem>) onSelected;

  final List<int>? preSelectedIds;
  final List<String>? preSelectedLabels;
  final List<LookupItem>? injectedItems;

  const LookupField({
    super.key,
    required this.title,
    required this.propertyId,
    this.isMultiSelect = false,
    required this.onSelected,
    this.preSelectedIds,
    this.preSelectedLabels,
    this.injectedItems,
  });

  @override
  State<LookupField> createState() => _LookupFieldState();
}

class _LookupFieldState extends State<LookupField> {
  List<LookupItem> _items = [];
  List<LookupItem> _selectedItems = [];
  bool _isLoading = false;

  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();

    final injected = widget.injectedItems ?? const <LookupItem>[];
    if (injected.isNotEmpty) {
      _items = List.from(injected);
      _selectedItems = _computeSelectedFromItems(_items);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _fetchLookupItems();
    });
  }

  @override
  void didUpdateWidget(covariant LookupField oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.propertyId != widget.propertyId) {
      _fetchLookupItems();
      return;
    }

    final oldIds = oldWidget.preSelectedIds ?? const <int>[];
    final newIds = widget.preSelectedIds ?? const <int>[];
    final idsChanged =
        oldIds.length != newIds.length || !oldIds.every(newIds.contains);

    final oldLabels = oldWidget.preSelectedLabels ?? const <String>[];
    final newLabels = widget.preSelectedLabels ?? const <String>[];
    final labelsChanged = oldLabels.length != newLabels.length ||
        !oldLabels.every((x) => newLabels.contains(x));

    final oldInjectedIds =
        (oldWidget.injectedItems ?? const <LookupItem>[])
            .map((e) => e.id)
            .toSet();
    final newInjectedIds =
        (widget.injectedItems ?? const <LookupItem>[]).map((e) => e.id).toSet();
    final injectedChanged = oldInjectedIds.length != newInjectedIds.length ||
        !oldInjectedIds.containsAll(newInjectedIds);

    if (injectedChanged || idsChanged || labelsChanged) {
      final merged = _mergeWithInjected(_items);
      if (!mounted) return;
      setState(() {
        _items = merged;
        _selectedItems = _computeSelectedFromItems(merged);
      });
    }
  }

  List<LookupItem> _mergeWithInjected(List<LookupItem> base) {
    final injected = widget.injectedItems;
    if (injected == null || injected.isEmpty) return base;

    final map = <int, LookupItem>{for (final i in base) i.id: i};
    for (final item in injected) {
      map.putIfAbsent(item.id, () => item);
    }
    return map.values.toList();
  }

  List<LookupItem> _computeSelectedFromItems(List<LookupItem> items) {
    final ids = widget.preSelectedIds ?? const <int>[];
    if (ids.isNotEmpty) {
      return items.where((it) => ids.contains(it.id)).toList();
    }

    final labels = (widget.preSelectedLabels ?? const <String>[])
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    if (labels.isNotEmpty) {
      return items
          .where((it) => labels.contains(it.displayValue.trim().toLowerCase()))
          .toList();
    }

    final selectedIds = _selectedItems.map((e) => e.id).toSet();
    return items.where((i) => selectedIds.contains(i.id)).toList();
  }

  Future<void> _fetchLookupItems() async {
    final int seq = ++_requestSeq;

    if (mounted) setState(() => _isLoading = true);

    try {
      final service = Provider.of<MFilesService>(context, listen: false);
      final fetched = await service.fetchLookupItems(widget.propertyId);

      if (!mounted || seq != _requestSeq) return;

      final merged = _mergeWithInjected(fetched);

      setState(() {
        _items = merged;
        _selectedItems = _computeSelectedFromItems(merged);
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
    } finally {
      if (!mounted || seq != _requestSeq) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return InkWell(
      onTap: () {
        FocusScope.of(context).unfocus();
        _showSelectionDialog();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedItems.isEmpty
                    ? 'Tap to select'
                    : _selectedItems.map((i) => i.displayValue).join(', '),
                style: TextStyle(
                  fontSize: 14,
                  color: _selectedItems.isEmpty
                      ? c.textSecondary
                      : c.textPrimary,
                  fontWeight: _selectedItems.isEmpty
                      ? FontWeight.w400
                      : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_isLoading)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.keyboard_arrow_down,
                color: c.textSecondary,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  void _showSelectionDialog() {
    final c = context.colors;
    final tempSelected = List<LookupItem>.from(_selectedItems);
    final searchController = TextEditingController();
    final focusNode = FocusNode();

    List<LookupItem> filtered = List.from(_items);

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final d = ctx.colors;
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 40,
            ),
            backgroundColor: d.surfaceElevated,
            surfaceTintColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header — brand blue in both modes
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                    decoration: const BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.vertical(
                        top: Radius.circular(20),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select ${widget.title}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                  ),

                  // Search bar
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: searchController,
                      focusNode: focusNode,
                      style: TextStyle(color: d.textPrimary),
                      cursorColor: d.brand,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(
                          color: d.textTertiary,
                          fontSize: 14,
                        ),
                        prefixIcon: Icon(
                          Icons.search,
                          color: d.textTertiary,
                          size: 20,
                        ),
                        filled: true,
                        fillColor: d.surfaceSunken,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: d.border),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: d.border),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: d.brand, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        isDense: true,
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(
                                  Icons.close,
                                  size: 16,
                                  color: d.textTertiary,
                                ),
                                onPressed: () {
                                  searchController.clear();
                                  setDialogState(
                                    () => filtered = List.from(_items),
                                  );
                                },
                              )
                            : null,
                      ),
                      onChanged: (q) {
                        setDialogState(() {
                          filtered = _items
                              .where((i) => i.displayValue
                                  .toLowerCase()
                                  .contains(q.toLowerCase()))
                              .toList();
                        });
                      },
                    ),
                  ),

                  // Result count
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 4,
                    ),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                        style: TextStyle(fontSize: 12, color: d.brand),
                      ),
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
                                Icon(
                                  Icons.search_off,
                                  size: 36,
                                  color: d.textTertiary,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  'No matches found',
                                  style: TextStyle(
                                    color: d.textTertiary,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: d.divider),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final isSelected =
                                  tempSelected.any((i) => i.id == item.id);

                              if (widget.isMultiSelect) {
                                return Material(
                                  color: isSelected
                                      ? d.brandTint
                                      : Colors.transparent,
                                  child: CheckboxListTile(
                                    title: Text(
                                      item.displayValue,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 14.5,
                                        height: 1.35,
                                        color: d.textPrimary,
                                      ),
                                    ),
                                    value: isSelected,
                                    activeColor: d.brand,
                                    checkColor: Colors.white,
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 4,
                                    ),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          if (!tempSelected
                                              .any((i) => i.id == item.id)) {
                                            tempSelected.add(item);
                                          }
                                        } else {
                                          tempSelected
                                              .removeWhere((i) => i.id == item.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              }

                              return Material(
                                color: isSelected
                                    ? d.brandTint
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (!mounted) return;
                                    setState(() => _selectedItems = [item]);

                                    final onSelected = widget.onSelected;
                                    final selectedItem = item;

                                    Navigator.pop(dialogContext);

                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      onSelected([selectedItem]);
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 20,
                                      vertical: 16,
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Text(
                                            item.displayValue,
                                            maxLines: 3,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              height: 1.35,
                                              color: d.textPrimary,
                                            ),
                                          ),
                                        ),
                                        if (isSelected)
                                          Icon(
                                            Icons.check_rounded,
                                            size: 18,
                                            color: d.brand,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // Multi-select confirm row
                  if (widget.isMultiSelect) ...[
                    Divider(height: 1, color: d.divider),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text(
                              'Cancel',
                              style: TextStyle(color: d.textSecondary),
                            ),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              if (!mounted) return;
                              setState(() => _selectedItems = tempSelected);

                              final onSelected = widget.onSelected;
                              final chosen =
                                  List<LookupItem>.from(tempSelected);

                              Navigator.pop(dialogContext);

                              WidgetsBinding.instance
                                  .addPostFrameCallback((_) {
                                onSelected(chosen);
                              });
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: d.brand,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 12,
                              ),
                            ),
                            child: Text('Done (${tempSelected.length})'),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 8),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}