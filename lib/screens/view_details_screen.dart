import 'package:flutter/material.dart';
import 'package:mfiles_app/models/group_filter.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/screens/view_items_screen.dart';
import 'package:provider/provider.dart';

import '../services/mfiles_service.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import '../models/view_content_item.dart';
import '../widgets/relationships_dropdown.dart';

class ViewDetailsScreen extends StatefulWidget {
  const ViewDetailsScreen({super.key, required this.view});

  final ViewItem view;

  @override
  State<ViewDetailsScreen> createState() => _ViewDetailsScreenState();
}

class _ViewDetailsScreenState extends State<ViewDetailsScreen> {
  String _filter = '';
  late Future<List<ViewContentItem>> _future;
  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id);
  }

  @override
  void dispose() {
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

  void _refreshThisView() {
    setState(() {
      _future = context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id);
    });
  }

  // Hide raw types completely, and never show "Group" / "MFFolderContentItemTypeViewFolder".
  // For objects: show ObjectTypeName or ClassTypeName.
  // For folders/groups: show nothing (null) OR a meaningful label if you ever add one.
  String? _subtitleLabel(ViewContentItem item) {
    if (item.isObject) {
      final t = (item.objectTypeName ?? '').trim();
      if (t.isNotEmpty) return t;
      final c = (item.classTypeName ?? '').trim();
      if (c.isNotEmpty) return c;
      return null;
    }

    // ✅ FIX: Hide Group + ViewFolder tags in UI
    if (item.isGroupFolder) return null;

    // Hide any other raw backend type strings too
    return null;
  }

  List<ViewContentItem> _applyFilter(List<ViewContentItem> items) {
    final q = _filter.trim().toLowerCase();
    if (q.isEmpty) return items;

    return items.where((o) {
      final title = o.title.toLowerCase();

      // ✅ FIX: searching should not depend on raw type or "group"
      final label = _subtitleLabel(o)?.toLowerCase() ?? '';

      return title.contains(q) || label.contains(q);
    }).toList();
  }

  Widget _buildInViewSearchBar() {
    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search in ${widget.view.name}...',
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

  Widget _buildRow(ViewContentItem item) {
    final subtitle = _subtitleLabel(item);

    final icon =
        (item.isGroupFolder || item.isViewFolder)
            ? Icons.folder_outlined
            : Icons.description_outlined;

    // Only objects can have relationships
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
          enabled: true,
          trailing: canExpand
              ? const Icon(Icons.expand_more, size: 18)
              : const Icon(Icons.chevron_right, size: 18),

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
          )
          ),

          // 👉 THIS is the relationships dropdown
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

          // Tap on header still opens object / folder
          onExpansionChanged: (expanded) {
            if (!expanded) return;

            // Expand shows relationships only
            // Actual navigation remains explicit:
          },

          // Tap on title area opens item
          // (ExpansionTile does not expose onTap, so wrap title)
        ),
      ),
    );
  }


  Future<void> _handleTap(ViewContentItem item) async {
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

      final deleted = await Navigator.push<bool>(
        context,
        MaterialPageRoute(builder: (_) => ObjectDetailsScreen(obj: obj)),
      );

      if (deleted == true) _refreshThisView();
      return;
    }

    if (item.isViewFolder) {
      // For MFFolderContentItemTypeViewFolder, child view id is item.id (confirmed: Staff -> id=117)
      final childViewId = item.id;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViewDetailsScreen(
            view: ViewItem(
              id: childViewId,
              name: item.title,
              count: 0,
            ),
          ),
        ),
      );
      return;
    }

    if (item.isGroupFolder) {
      final propId = item.propId;
      final propDatatype = item.propDatatype;

      if (propId == null || propId.trim().isEmpty || propDatatype == null || propDatatype.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('There are no items in this view.')),
        );
        return;
      }

      final svc = context.read<MFilesService>();
      final vid = (item.viewId > 0) ? item.viewId : widget.view.id;

      try {
        final items = await svc.fetchViewPropItems(
          viewId: vid,
          filters: [GroupFilter(propId: propId, propDatatype: propDatatype)],
        );

        if (!context.mounted) return;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ViewItemsScreen(
              title: item.title,
              items: items,
              parentViewId: vid,
              filters: [GroupFilter(propId: propId, propDatatype: propDatatype)],
              ),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    }
 
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unsupported item type')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 12,
        title: Text(widget.view.name, maxLines: 1, overflow: TextOverflow.ellipsis),
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
          if (_showSearch) _buildInViewSearchBar(),
          Expanded(
            child: FutureBuilder<List<ViewContentItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(child: Text('Error: ${snap.error}'));
                }

                final items = snap.data ?? [];
                final filtered = _applyFilter(items);

                if (items.isEmpty) {
                  return const Center(child: Text('No items found'));
                }

                if (filtered.isEmpty) {
                  return const Center(child: Text('No matches'));
                }

                return RefreshIndicator(
                  onRefresh: () async {
                    _refreshThisView();
                    await _future;
                  },
                  child: ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(16),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _buildRow(filtered[i]),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ObjectsListScreen extends StatefulWidget {
  const _ObjectsListScreen({required this.title, required this.objects});

  final List<ViewObject> objects;
  final String title;

  @override
  State<_ObjectsListScreen> createState() => _ObjectsListScreenState();
}

class _ObjectsListScreenState extends State<_ObjectsListScreen> {
  late List<ViewObject> _objects;

  @override
  void initState() {
    super.initState();
    _objects = List<ViewObject>.from(widget.objects);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        titleSpacing: 12,
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
      body: _objects.isEmpty
          ? const Center(child: Text('No objects found'))
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _objects.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final obj = _objects[i];
                return InkWell(
                  onTap: () async {
                    final deleted = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => ObjectDetailsScreen(obj: obj)),
                    );

                    if (deleted == true && mounted) {
                      setState(() {
                        _objects.removeWhere((x) => x.id == obj.id);
                      });
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.description_outlined, size: 18, color: Color.fromRGBO(25, 76, 129, 1)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                obj.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                obj.objectTypeName.isNotEmpty ? obj.objectTypeName : obj.classTypeName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
