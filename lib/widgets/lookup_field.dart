import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mfiles_app/models/lookup_item.dart';
import 'package:mfiles_app/services/mfiles_service.dart';

class LookupField extends StatefulWidget {
  final String title;
  final int propertyId;
  final bool isMultiSelect;
  final Function(List<LookupItem>) onSelected;

  final List<int>? preSelectedIds;

  // fallback when API gives display text but not IDs
  final List<String>? preSelectedLabels;

  const LookupField({
    super.key,
    required this.title,
    required this.propertyId,
    this.isMultiSelect = false,
    required this.onSelected,
    this.preSelectedIds,
    this.preSelectedLabels,
  });

  @override
  State<LookupField> createState() => _LookupFieldState();
}

class _LookupFieldState extends State<LookupField> {
  List<LookupItem> _items = [];
  List<LookupItem> _selectedItems = [];
  bool _isLoading = false;

  static const _primaryBlue = Color(0xFF072F5F);

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

    if ((_items.isNotEmpty) && (idsChanged || labelsChanged)) {
      if (!mounted) return;
      setState(() {
        _selectedItems = _computeSelectedFromItems(_items);
      });
    }
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
      final items = await service.fetchLookupItems(widget.propertyId);

      if (!mounted || seq != _requestSeq) return;

      setState(() {
        _items = items;
        _selectedItems = _computeSelectedFromItems(items);
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
                  // ── Header (no search toggle icon needed anymore) ──
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
                        fillColor: Colors.grey.shade50,
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
                            fontSize: 12, color: Colors.grey.shade500),
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
                                      color: Colors.grey.shade500,
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

                              return Material(
                                color: isSelected
                                    ? const Color(0xFFEFF6FF)
                                    : Colors.transparent,
                                child: InkWell(
                                  onTap: () {
                                    if (!mounted) return;
                                    setState(
                                        () => _selectedItems = [item]);
                                    widget.onSelected([item]);
                                    Navigator.pop(dialogContext);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 20, vertical: 14),
                                    child: Row(
                                      children: [
                                        Expanded(
                                            child:
                                                Text(item.displayValue)),
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
                            onPressed: () {
                              if (!mounted) return;
                              setState(
                                  () => _selectedItems = tempSelected);
                              widget.onSelected(tempSelected);
                              Navigator.pop(dialogContext);
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