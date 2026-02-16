import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mfiles_app/models/lookup_item.dart';
import 'package:mfiles_app/services/mfiles_service.dart';

class LookupField extends StatefulWidget {
  final String title;
  final int propertyId;
  final bool isMultiSelect;
  final Function(List<LookupItem>) onSelected;
  final List<int>? preSelectedIds; // NEW: Pass in already selected IDs

  const LookupField({
    super.key,
    required this.title,
    required this.propertyId,
    this.isMultiSelect = false,
    required this.onSelected,
    this.preSelectedIds,
  });

  @override
  State<LookupField> createState() => _LookupFieldState();
}

class _LookupFieldState extends State<LookupField> {
  List<LookupItem> _items = [];
  List<LookupItem> _selectedItems = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchLookupItems();
  }

  Future<void> _fetchLookupItems() async {
    setState(() => _isLoading = true);
    try {
      final service = Provider.of<MFilesService>(context, listen: false);
      final items = await service.fetchLookupItems(widget.propertyId);
      setState(() {
        _items = items;
        // Pre-select items based on preSelectedIds
        if (widget.preSelectedIds != null && widget.preSelectedIds!.isNotEmpty) {
          _selectedItems = items.where((item) => widget.preSelectedIds!.contains(item.id)).toList();
        }
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _showSelectionDialog,
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
                  color: _selectedItems.isEmpty ? Colors.grey.shade600 : const Color(0xFF1A1A1A),
                  fontWeight: _selectedItems.isEmpty ? FontWeight.w400 : FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down, color: Colors.grey.shade600, size: 20),
          ],
        ),
      ),
    );
  }

  void _showSelectionDialog() {
    // Create a local copy to avoid modifying the original until confirmed
    final tempSelected = List<LookupItem>.from(_selectedItems);
    
    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF072F5F).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  widget.isMultiSelect ? Icons.checklist_rounded : Icons.check_circle_outline,
                  color: const Color(0xFF072F5F),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Select ${widget.title}',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(0, 16, 0, 0),
          content: SizedBox(
            width: double.maxFinite,
            child: _isLoading
                ? const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: CircularProgressIndicator()),
                  )
                : _items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.inbox_outlined, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 12),
                              Text(
                                'No items available',
                                style: TextStyle(color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: _items.length,
                        separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          final isSelected = tempSelected.any((i) => i.id == item.id);

                          return widget.isMultiSelect
                              ? CheckboxListTile(
                                  title: Text(
                                    item.displayValue,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: isSelected ? const Color(0xFF072F5F) : Colors.black87,
                                    ),
                                  ),
                                  value: isSelected,
                                  activeColor: const Color(0xFF072F5F),
                                  checkColor: Colors.white,
                                  controlAffinity: ListTileControlAffinity.leading,
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                                  onChanged: (value) {
                                    setDialogState(() {
                                      if (value == true) {
                                        tempSelected.add(item);
                                      } else {
                                        tempSelected.removeWhere((i) => i.id == item.id);
                                      }
                                    });
                                  },
                                )
                              : ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                                  title: Text(
                                    item.displayValue,
                                    style: TextStyle(
                                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                                      color: isSelected ? const Color(0xFF072F5F) : Colors.black87,
                                    ),
                                  ),
                                  leading: isSelected
                                      ? const Icon(Icons.check_circle, color: Color(0xFF072F5F), size: 22)
                                      : Icon(Icons.circle_outlined, color: Colors.grey.shade400, size: 22),
                                  onTap: () {
                                    setState(() => _selectedItems = [item]);
                                    widget.onSelected([item]);
                                    Navigator.pop(dialogContext);
                                  },
                                );
                        },
                      ),
          ),
          actions: widget.isMultiSelect
              ? [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(
                      'Cancel',
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      setState(() => _selectedItems = tempSelected);
                      widget.onSelected(tempSelected);
                      Navigator.pop(dialogContext);
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF072F5F),
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: Text(
                      'Done (${tempSelected.length})',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ]
              : null,
        ),
      ),
    );
  }
}