import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mfiles_app/models/lookup_item.dart';
import 'package:mfiles_app/services/mfiles_service.dart';

class LookupField extends StatefulWidget {
  final String title;
  final int propertyId;
  final bool isMultiSelect;
  final Function(List<LookupItem>) onSelected;

  const LookupField({
    required this.title,
    required this.propertyId,
    this.isMultiSelect = false,
    required this.onSelected,
  });

  @override
  _LookupFieldState createState() => _LookupFieldState();
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
      setState(() => _items = items);
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: _showSelectionDialog,
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _selectedItems.isEmpty
                    ? 'Select ${widget.title}'
                    : _selectedItems.map((i) => i.displayValue).join(', '),
              ),
            ),
            Icon(Icons.arrow_drop_down),
          ],
        ),
      ),
    );
  }

  void _showSelectionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Select ${widget.title}'),
        content: SizedBox(
          width: double.maxFinite,
          child: _isLoading
              ? Center(child: CircularProgressIndicator())
              : ListView.builder(
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (context, index) {
                    final item = _items[index];
                    final isSelected = _selectedItems.any((i) => i.id == item.id);
                    
                    return widget.isMultiSelect
                        ? CheckboxListTile(
                            title: Text(item.displayValue),
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedItems.add(item);
                                } else {
                                  _selectedItems.removeWhere((i) => i.id == item.id);
                                }
                              });
                            },
                          )
                        : ListTile(
                            title: Text(item.displayValue),
                            onTap: () {
                              setState(() => _selectedItems = [item]);
                              widget.onSelected(_selectedItems);
                              Navigator.pop(context);
                            },
                          );
                  },
                ),
        ),
        actions: widget.isMultiSelect
            ? [
                TextButton(
                  onPressed: () {
                    Navigator.pop(context);
                    widget.onSelected(_selectedItems);
                  },
                  child: Text('OK'),
                ),
              ]
            : null,
      ),
    );
  }
}