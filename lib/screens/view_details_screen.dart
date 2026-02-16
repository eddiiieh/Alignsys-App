import 'package:flutter/material.dart';
import 'package:mfiles_app/models/group_filter.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/screens/view_items_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:provider/provider.dart';

import '../models/view_item.dart';
import '../models/view_object.dart';
import '../models/view_content_item.dart';
import '../widgets/relationships_dropdown.dart';
import '../widgets/object_info_dropdown.dart';

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

  final ScrollController _viewScroll = ScrollController();

  // Track which item is currently expanded for info
  int? _expandedInfoItemId;
  // Track which item is currently expanded for relationships
  int? _expandedRelationshipsItemId;

  bool _dataLoaded = false;

  // ✅ Add debounce timestamp
  DateTime? _lastInfoToggle;
  DateTime? _lastRelationshipsToggle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ✅ Only fetch once, not on every dependency change
    if (!_dataLoaded) {
      _dataLoaded = true;
      _future = context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id);
    }
  } // ✅ FIX: This closing brace was missing!

  @override
  void dispose() {
    _viewScroll.dispose();
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
      _dataLoaded = false; // ✅ Reset data loaded flag
      _future = context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id);
    });
  }

  // ✅ ADD: Debounced toggle for info
  void _toggleInfo(int itemId) {
    final now = DateTime.now();
    if (_lastInfoToggle != null && now.difference(_lastInfoToggle!) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastInfoToggle = now;

    setState(() {
      if (_expandedInfoItemId == itemId) {
        _expandedInfoItemId = null;
      } else {
        _expandedInfoItemId = itemId;
        _expandedRelationshipsItemId = null;
      }
    });
  }

  // ✅ ADD: Debounced toggle for relationships
  void _toggleRelationships(int itemId) {
    final now = DateTime.now();
    if (_lastRelationshipsToggle != null && now.difference(_lastRelationshipsToggle!) < const Duration(milliseconds: 300)) {
      return;
    }
    _lastRelationshipsToggle = now;

    setState(() {
      if (_expandedRelationshipsItemId == itemId) {
        _expandedRelationshipsItemId = null;
      } else {
        _expandedRelationshipsItemId = itemId;
        _expandedInfoItemId = null;
      }
    });
  }

  String? _subtitleLabel(ViewContentItem item) {
    if (item.isObject) {
      final t = (item.objectTypeName ?? '').trim();
      if (t.isNotEmpty) return t;
      final c = (item.classTypeName ?? '').trim();
      if (c.isNotEmpty) return c;
      return null;
    }

    if (item.isGroupFolder) return null;
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
    final svc = context.watch<MFilesService>();
    final icon = svc.iconForContentItem(item);

    final bool isObject = item.isObject && item.id > 0;
    final bool hasRelationships = isObject && item.objectTypeId > 0 && item.classId > 0;

    final bool infoExpanded = _expandedInfoItemId == item.id;
    final bool relationshipsExpanded = _expandedRelationshipsItemId == item.id;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          // Main row
          InkWell(
            onTap: () => _handleTap(item),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Row(
                children: [
                  // Relationships chevron (left side)
                  if (hasRelationships) ...[
                    InkWell(
                      onTap: () => _toggleRelationships(item.id), // ✅ Use debounced method
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          relationshipsExpanded ? Icons.expand_more : Icons.chevron_right,
                          size: 18,
                          color: const Color(0xFF072F5F),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                  ] else
                    const SizedBox(width: 4),

                  // Icon
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF072F5F).withOpacity(0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, size: 18, color: const Color.fromRGBO(25, 76, 129, 1)),
                  ),
                  const SizedBox(width: 10),

                  // Title & subtitle
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

                  // Info icon (right side) - only for objects
                  if (isObject) ...[
                    const SizedBox(width: 8),
                    InkWell(
                      onTap: () => _toggleInfo(item.id), // ✅ Use debounced method
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF072F5F).withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          infoExpanded ? Icons.info : Icons.info_outline,
                          size: 18,
                          color: const Color(0xFF072F5F),
                        ),
                      ),
                    ),
                  ] else
                    Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),

          // Info dropdown
          if (infoExpanded && isObject) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            ObjectInfoDropdown(
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
          ],

          // Relationships dropdown
          if (relationshipsExpanded && hasRelationships) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              child: RelationshipsDropdown(
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
            ),
          ],
        ],
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

                // ✅ NO warm-up calls here - already done in service
                
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
                  child: Scrollbar(
                    controller: _viewScroll,
                    thumbVisibility: false,
                    interactive: true,
                    thickness: 6,
                    radius: const Radius.circular(8),
                    child: ListView.builder(
                      controller: _viewScroll,
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(16),
                      itemCount: filtered.length,
                      itemBuilder: (context, i) => _buildRow(filtered[i]),
                    ),
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