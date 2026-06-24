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

  // fallback when API gives display text but not IDs
  final List<String>? preSelectedLabels;

  // Items the parent already knows about (e.g. the currently selected
  // items, or an object just created via the inline "+" quick-create flow)
  // that may not yet exist in the fetched lookup list. Merged into the
  // fetched list so they display correctly without waiting for a refetch.
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

  static const _primaryBlue = AppColors.primary;

  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
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

    final oldInjectedIds = (oldWidget.injectedItems ?? const <LookupItem>[])
        .map((e) => e.id)
        .toSet();
    final newInjectedIds = (widget.injectedItems ?? const <LookupItem>[])
        .map((e) => e.id)
        .toSet();
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

  /// Merges [widget.injectedItems] into [base], preferring the server's
  /// copy of an id when both exist, and only adding injected items the
  /// fetched list doesn't already contain.
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

    // fallback by label match (case-insensitive, trimmed)
    final labels = (widget.preSelectedLabels ?? const <String>[])
        .map((s) => s.trim().toLowerCase())
        .where((s) => s.isNotEmpty)
        .toSet();

    if (labels.isNotEmpty) {
      return items
          .where((it) => labels.contains(it.displayValue.trim().toLowerCase()))
          .toList();
    }

    // keep existing selection only if still present
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
                      ? Colors.grey.shade600
                      : const Color(0xFF1A1A1A),
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
                  child: CircularProgressIndicator(strokeWidth: 2))
            else
              Icon(Icons.keyboard_arrow_down,
                  color: Colors.grey.shade600, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSelectionDialog() {
    final tempSelected = List<LookupItem>.from(_selectedItems);
    final searchController = TextEditingController();
    final focusNode = FocusNode();

    List<LookupItem> filtered = List.from(_items);

    // Request focus once after the dialog's first frame — outside the
    // StatefulBuilder so it doesn't re-schedule on every setDialogState rebuild.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (focusNode.canRequestFocus) focusNode.requestFocus();
    });

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(ctx).size.height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Header ──
                  Container(
                    padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
                    decoration: const BoxDecoration(
                      color: _primaryBlue,
                      borderRadius:
                          BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Select ${widget.title}',
                            style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Colors.white),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close,
                              color: Colors.white, size: 20),
                          onPressed: () => Navigator.pop(dialogContext),
                        ),
                      ],
                    ),
                  ),

                  // ── Always-active search bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: TextField(
                      controller: searchController,
                      focusNode: focusNode,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(
                            color: Colors.grey.shade400, fontSize: 14),
                        prefixIcon: Icon(Icons.search,
                            color: Colors.grey.shade400, size: 20),
                        filled: true,
                        fillColor: AppColors.surfaceLight,
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
                          borderSide:
                              const BorderSide(color: _primaryBlue, width: 2),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 12),
                        isDense: true,
                        suffixIcon: searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.close,
                                    size: 16, color: Colors.grey.shade400),
                                onPressed: () {
                                  searchController.clear();
                                  setDialogState(
                                      () => filtered = List.from(_items));
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

                  // ── Result count ──
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '${filtered.length} result${filtered.length == 1 ? '' : 's'}',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.surfaceLight),
                      ),
                    ),
                  ),

                  // ── List ──
                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off,
                                    size: 36, color: Colors.grey.shade300),
                                const SizedBox(height: 8),
                                Text(
                                  'No matches found',
                                  style: TextStyle(
                                      color: AppColors.surfaceLight,
                                      fontSize: 13),
                                ),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            padding:
                                const EdgeInsets.symmetric(vertical: 8),
                            itemCount: filtered.length,
                            separatorBuilder: (_, __) =>
                                Divider(height: 1, color: Colors.grey.shade100),
                            itemBuilder: (context, index) {
                              final item = filtered[index];
                              final isSelected =
                                  tempSelected.any((i) => i.id == item.id);

                              if (widget.isMultiSelect) {
                                return Material(
                                  color: isSelected
                                      ? const Color(0xFFEFF6FF)
                                      : Colors.transparent,
                                  child: CheckboxListTile(
                                    title: Text(item.displayValue),
                                    value: isSelected,
                                    activeColor: _primaryBlue,
                                    onChanged: (value) {
                                      setDialogState(() {
                                        if (value == true) {
                                          if (!tempSelected
                                              .any((i) => i.id == item.id)) {
                                            tempSelected.add(item);
                                          }
                                        } else {
                                          tempSelected.removeWhere(
                                              (i) => i.id == item.id);
                                        }
                                      });
                                    },
                                  ),
                                );
                              }

                              // ── Single-select: pop first, then fire onSelected
                              // via postFrameCallback so the checking dialog has a
                              // clean navigator stack to push onto.
                              return Material(
                                color: isSelected
                                    ? const Color(0xFFEFF6FF)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    debugPrint('✅ LookupField onTap fired for item: ${item.displayValue}');
                                    if (!mounted) return;
                                    setState(() => _selectedItems = [item]);

                                    // Capture before closing — the widget may be
                                    // disposed by the time the callback fires.
                                    final onSelected = widget.onSelected;
                                    final selectedItem = item;

                                    Navigator.pop(dialogContext);

                                    // Fire after the lookup dialog is fully gone.
                                    WidgetsBinding.instance
                                        .addPostFrameCallback((_) {
                                      onSelected([selectedItem]);
                                    });
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                            child: Text(item.displayValue)),
                                        if (isSelected)
                                          const Icon(Icons.check_rounded,
                                              size: 18,
                                              color: Color(0xFF2563EB)),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),

                  // ── Multi-select confirm row ──
                  if (widget.isMultiSelect) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(dialogContext),
                            child: Text('Cancel',
                                style: TextStyle(
                                    color: Colors.grey.shade700)),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            // ── Multi-select: same fix — pop first, then fire
                            // onSelected after the dialog is fully dismissed.
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
                              backgroundColor: _primaryBlue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 20, vertical: 12),
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
    // Do NOT manually dispose focusNode or searchController here.
    // They are local to this dialog and never attached to the persistent
    // widget tree, so Flutter cleans them up when the route is fully removed.
    // Disposing them early triggers "FocusNode used after being disposed"
    // during the dialog's closing animation.
  }
}