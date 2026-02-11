import 'package:flutter/material.dart';
import 'package:mfiles_app/models/group_filter.dart';
import 'package:provider/provider.dart';

import '../models/view_content_item.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import '../services/mfiles_service.dart';
import 'object_details_screen.dart';
import 'view_details_screen.dart';
import '../widgets/relationships_dropdown.dart';

class ViewItemsScreen extends StatefulWidget {
  final String title;
  final int parentViewId; // keep the real viewId for drilling groups
  final List<ViewContentItem> items;

  /// accumulated group selections in order (Year -> Month -> ...)
  final List<GroupFilter> filters;

  const ViewItemsScreen({
    super.key,
    required this.title,
    required this.parentViewId,
    required this.items,
    required this.filters,
  });

  @override
  State<ViewItemsScreen> createState() => _ViewItemsScreenState();
}

class _ViewItemsScreenState extends State<ViewItemsScreen> {
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;
  String _filter = '';

  late List<ViewContentItem> _items;

  final ScrollController _itemsScroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _items = widget.items;

    // ✅ onload warm-up (runs once when this screen is created)
    // Uses MFilesService cache + de-dupe to avoid repeated calls.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<MFilesService>().warmExtensionsForItems(_items);
    });
  }

  @override
  void didUpdateWidget(covariant ViewItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _items = widget.items;

      // ✅ warm-up again if a new list is pushed in
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MFilesService>().warmExtensionsForItems(_items);
      });
    }
  }

  @override
  void dispose() {
    _itemsScroll.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _showSearch = !_showSearch;
      if (!_showSearch) {
        _filter = '';
        _searchController.clear();
      }
    });
  }

  String? _subtitleLabel(ViewContentItem item) {
    if (item.isObject) {
      final t = (item.objectTypeName ?? '').trim();
      if (t.isNotEmpty) return t;
      final c = (item.classTypeName ?? '').trim();
      if (c.isNotEmpty) return c;
    }
    return null;
  }

  List<ViewContentItem> _applyFilter(List<ViewContentItem> items) {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return items;

    return items.where((o) {
      final title = o.title.toLowerCase();
      final label = _subtitleLabel(o)?.toLowerCase() ?? '';
      return title.contains(q) || label.contains(q);
    }).toList();
  }

  Widget _buildRow(ViewContentItem item) {
    final subtitle = _subtitleLabel(item);

    final svc = context.watch<MFilesService>();

    final IconData icon;
    if (item.isGroupFolder || item.isViewFolder) {
      icon = Icons.folder_outlined;
    } else {
      icon = svc.iconForContentItem(item);
    }

    final bool canExpand = item.isObject && item.id != 0 && item.objectTypeId != 0 && item.classId != 0;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          trailing: canExpand
              ? const Icon(Icons.expand_more, size: 18)
              : Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _handleTap(item),
            child: Row(
              children: [
                Icon(icon, size: 18, color: const Color.fromRGBO(25, 76, 129, 1)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                      ),
                      if (subtitle != null && subtitle.trim().isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          children: canExpand
              ? [
                  RelationshipsDropdown(
                    obj: ViewObject(
                      id: item.id,
                      title: item.title,
                      objectTypeId: item.objectTypeId,
                      classId: item.classId,
                      versionId: item.versionId,
                      objectTypeName: item.objectTypeName ?? '',
                      classTypeName: item.classTypeName ?? '',
                      displayId: item.displayId ?? '',
                      createdUtc: item.createdUtc,
                      lastModifiedUtc: item.lastModifiedUtc,
                    ),
                  ),
                ]
              : const [],
        ),
      ),
    );
  }

  Future<void> _handleTap(ViewContentItem item) async {
    // 1) REAL OBJECT -> details
    if (item.isObject) {
      final obj = ViewObject(
        id: item.id,
        title: item.title,
        objectTypeId: item.objectTypeId,
        classId: item.classId,
        versionId: item.versionId,
        objectTypeName: item.objectTypeName ?? '',
        classTypeName: item.classTypeName ?? '',
        displayId: item.displayId ?? '',
        createdUtc: item.createdUtc,
        lastModifiedUtc: item.lastModifiedUtc,
      );

      await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ObjectDetailsScreen(obj: obj)),
      );
      return;
    }

    // 2) VIEW FOLDER -> open child view
    if (item.isViewFolder) {
      final childViewId = item.id;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViewDetailsScreen(
            view: ViewItem(id: childViewId, name: item.title, count: 0),
          ),
        ),
      );
      return;
    }

    // 3) GROUP FOLDER -> drill down (send FULL group path)
    if (item.isGroupFolder) {
      String key = item.propId?.trim() ?? '';
      String dtype = item.propDatatype?.trim() ?? '';

      if (key.isEmpty || dtype.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('There are no items in this view.')),
        );
        return;
      }

      // ✅ IMPORTANT: match web behavior for Month group:
      // Month is sent as "05" with MFDatatypeText (do NOT convert to int)
      final isTwoDigitMonth = RegExp(r'^(0[1-9]|1[0-2])$').hasMatch(key);
      if (isTwoDigitMonth) {
        dtype = 'MFDatatypeText';
        // keep key exactly e.g. "05"
      }

      final svc = context.read<MFilesService>();
      final vid = (item.viewId > 0) ? item.viewId : widget.parentViewId;

      final nextFilters = <GroupFilter>[
        ...widget.filters,
        GroupFilter(propId: key, propDatatype: dtype),
      ];

      final children = await svc.fetchViewPropItems(
        viewId: vid,
        filters: nextFilters,
      );

      if (!context.mounted) return;

      // ✅ warm-up for the next level list too (pre-cache icons)
      context.read<MFilesService>().warmExtensionsForItems(children);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViewItemsScreen(
            title: item.title,
            parentViewId: vid,
            items: children,
            filters: nextFilters,
          ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unsupported item type')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applyFilter(_items);

    // ✅ safe to call; your service should de-dupe cached + in-flight IDs
    context.read<MFilesService>().warmExtensionsForItems(filtered);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 12,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          if (_showSearch) _buildSearchBar(),
          Expanded(
            child: filtered.isEmpty
                ? const Center(child: Text('No items found'))
                : Scrollbar(
                    controller: _itemsScroll,
                    thumbVisibility: false, // only while scrolling
                    interactive: true,
                    thickness: 6,
                    radius: const Radius.circular(8),
                    child: ListView.separated(
                      controller: _itemsScroll,
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) => _buildRow(filtered[i]),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search...',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: Colors.grey.shade300),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color.fromRGBO(25, 76, 129, 1), width: 2),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          suffixIcon: _filter.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    setState(() {
                      _filter = '';
                      _searchController.clear();
                    });
                  },
                ),
        ),
        onChanged: (v) => setState(() => _filter = v),
      ),
    );
  }
}
