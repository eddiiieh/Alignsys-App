import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mfiles_app/models/group_filter.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/screens/view_items_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/utils/delete_object_helper.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
import 'package:mfiles_app/widgets/object_info_dropdown.dart';
import 'package:mfiles_app/widgets/relationships_dropdown.dart';
import 'package:provider/provider.dart';

import '../models/view_content_item.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import 'package:mfiles_app/widgets/breadcrumb_bar.dart';

class ViewDetailsScreen extends StatefulWidget {
  const ViewDetailsScreen({
    super.key,
    required this.view,
    this.parentSection,
  });

  final ViewItem view;
  final String? parentSection;

  @override
  State<ViewDetailsScreen> createState() => _ViewDetailsScreenState();
}

class _ViewDetailsScreenState extends State<ViewDetailsScreen> {
  String _filter = '';
  late Future<List<ViewContentItem>> _future;

  final TextEditingController _searchController = TextEditingController();
  bool _showSearch = false;

  final ScrollController _viewScroll = ScrollController();

  int? _expandedInfoItemId;
  int? _expandedRelationshipsItemId;

  bool _dataLoaded = false;

  DateTime? _lastInfoToggle;
  DateTime? _lastRelationshipsToggle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dataLoaded) {
      _dataLoaded = true;
      _future =
          context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id);
    }
  }

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
      _dataLoaded = false;
      _future =
          context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id);
    });
  }

  void _toggleInfo(int itemId) {
    final now = DateTime.now();
    if (_lastInfoToggle != null &&
        now.difference(_lastInfoToggle!) < const Duration(milliseconds: 300)) {
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

  void _toggleRelationships(int itemId) {
    final now = DateTime.now();
    if (_lastRelationshipsToggle != null &&
        now.difference(_lastRelationshipsToggle!) <
            const Duration(milliseconds: 300)) {
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

  Widget _buildBreadcrumbs() {
    return BreadcrumbBar(segments: [
      BreadcrumbSegment(
        label: 'Home',
        icon: Icons.home_rounded,
        onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      ),
      BreadcrumbSegment(label: widget.view.name),
    ]);
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
            borderSide: const BorderSide(
              color: Color.fromRGBO(25, 76, 129, 1),
              width: 2,
            ),
          ),
          filled: true,
          fillColor: Colors.white,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          suffixIcon: _filter.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => setState(() {
                    _filter = '';
                    _searchController.clear();
                  }),
                ),
        ),
        onChanged: (v) => setState(() => _filter = v),
      ),
    );
  }

  // ─── ROW (Fix A: Material + clipBehavior) ─────────────────────────────────

  Widget _buildRow(ViewContentItem item, bool isLast) {
    final subtitle = _subtitleLabel(item);
    final svc = context.watch<MFilesService>();

    final bool isObject = item.isObject && item.id > 0;

    // Relationships need full metadata
    final bool hasRelationships =
        isObject && item.objectTypeId > 0 && item.classId > 0;

    // Long-press delete only needs valid object id
    final bool canDelete = isObject;

    final bool infoExpanded = _expandedInfoItemId == item.id;
    final bool relationshipsExpanded = _expandedRelationshipsItemId == item.id;

    // Dim other rows when one is expanded
    final bool isDimmed = _expandedInfoItemId != null && !infoExpanded;

    final ViewObject? asViewObj = canDelete
        ? ViewObject(
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
          )
        : null;

    final BorderRadius radius = isLast
        ? const BorderRadius.vertical(bottom: Radius.circular(12))
        : BorderRadius.zero;

    return Column(
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isDimmed ? 0.45 : 1.0,
          child: Material(
            color: infoExpanded
                ? const Color(0xFF072F5F).withOpacity(0.03)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: infoExpanded
                  ? const BorderSide(color: Color(0xFF072F5F), width: 1.5)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias, // <- stops the blue wash
            elevation: 0,
            child: InkWell(
              borderRadius: radius,
              // optional: if you want ZERO overlay color
              // splashColor: Colors.transparent,
              // highlightColor: Colors.transparent,
              onTap: () {
                if (isDimmed) {
                  setState(() => _expandedInfoItemId = null);
                  return;
                }
                _handleTap(item);
              },
              onLongPress: canDelete
                  ? () => showLongPressDeleteSheet(
                        context,
                        obj: asViewObj!,
                        onDeleted: _refreshThisView,
                      )
                  : null,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 12),
                    child: Row(
                      children: [
                        // Relationships chevron
                        if (hasRelationships) ...[
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggleRelationships(item.id),
                              borderRadius: BorderRadius.circular(4),
                              child: Padding(
                                padding: const EdgeInsets.all(4),
                                child: Icon(
                                  relationshipsExpanded
                                      ? Icons.expand_more
                                      : Icons.chevron_right,
                                  size: 18,
                                  color: const Color(0xFF072F5F),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ] else
                          const SizedBox(width: 4),

                        // Icon
                        (item.isObject && svc.isDocumentContentItem(item))
                            ? FileTypeBadge(
                                extension:
                                    svc.cachedExtensionForObject(item.id) ?? '',
                                size: 40,
                              )
                            : const SizedBox(
                                width: 28,
                                height: 28,
                                child: Icon(
                                  Icons.folder_rounded,
                                  color: Color(0xFF072F5F),
                                  size: 22,
                                ),
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
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (subtitle != null &&
                                  subtitle.trim().isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text(
                                  subtitle,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // Info icon – objects only
                        if (isObject) ...[
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.transparent,
                            child: InkWell(
                              onTap: () => _toggleInfo(item.id),
                              borderRadius: BorderRadius.circular(20),
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF072F5F)
                                      .withOpacity(0.08),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  infoExpanded
                                      ? Icons.keyboard_arrow_up_rounded
                                      : Icons.info_outline,
                                  size: 18,
                                  color: const Color(0xFF072F5F),
                                ),
                              ),
                            ),
                          ),
                        ] else
                          Icon(Icons.chevron_right,
                              size: 18, color: Colors.grey.shade500),
                      ],
                    ),
                  ),

                  // Info dropdown
                  if (infoExpanded && isObject) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    ObjectInfoDropdown(obj: asViewObj!),
                  ],

                  // Relationships dropdown
                  if (relationshipsExpanded && hasRelationships) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: RelationshipsDropdown(obj: asViewObj!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 1, thickness: 1, color: Colors.grey.shade100),
      ],
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
        MaterialPageRoute(
          builder: (_) => ObjectDetailsScreen(
            obj: obj,
            parentViewName: widget.view.name,
            parentSection: widget.parentSection,
          ),
        ),
      );

      if (deleted == true) _refreshThisView();
      return;
    }

    if (item.isViewFolder) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ViewDetailsScreen(
            view: ViewItem(id: item.id, name: item.title, count: 0),
            parentSection: widget.parentSection,
          ),
        ),
      );
      return;
    }

    if (item.isGroupFolder) {
      final propId = item.propId;
      final propDatatype = item.propDatatype;

      if (propId == null ||
          propId.trim().isEmpty ||
          propDatatype == null ||
          propDatatype.trim().isEmpty) {
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
              parentViewName: widget.view.name,
              parentSection: widget.parentSection,
            ),
          ),
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.toString())));
      }
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Unsupported item type')),
    );
  }

  // ─── SCAFFOLD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 12,
        title: Text(
          widget.view.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
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
          _buildBreadcrumbs(),
          if (_showSearch) _buildInViewSearchBar(),
          Expanded(
            child: FutureBuilder<List<ViewContentItem>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snap.hasError) {
                  final error = snap.error.toString();
                  final isEmpty = error.contains('400') ||
                      error.contains('cannot be used to define a grouping level') ||
                      error.contains('Unspecified error') ||
                      error.contains('No items') ||
                      error.contains('empty');

                  return isEmpty ? _buildEmptyState() : _buildErrorState(error);
                }

                final items = snap.data ?? [];
                final filtered = _applyFilter(items);

                if (items.isEmpty) return _buildEmptyState();
                if (filtered.isEmpty) return _buildNoMatchesState();

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
                    child: Stack(
                      children: [
                        ListView(
                          controller: _viewScroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(8),
                          children: [
                            Container(
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
                                children: List.generate(
                                  filtered.length,
                                  (i) => _buildRow(
                                    filtered[i],
                                    i == filtered.length - 1,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (_expandedInfoItemId != null)
                        Positioned.fill(
                          child: GestureDetector(
                            behavior: HitTestBehavior.translucent,
                            onTap: () => setState(() => _expandedInfoItemId = null),
                            child: const SizedBox.expand(),
                          ),
                        ),
                      ],
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

  // ─── EMPTY / ERROR / NO-MATCH STATES ─────────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.inbox_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Items Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This view is currently empty',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () => setState(() {
                _dataLoaded = false;
                _future = context
                    .read<MFilesService>()
                    .fetchObjectsInViewRaw(widget.view.id);
              }),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF072F5F),
                side: BorderSide(
                  color: const Color(0xFF072F5F).withOpacity(0.3),
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    String msg = 'Unable to load this view';
    if (error.contains('cannot be used to define a grouping level')) {
      msg = 'This view has a configuration issue';
    } else if (error.contains('400')) {
      msg = 'Unable to access this view';
    } else if (error.contains('403') || error.contains('Forbidden')) {
      msg = "You don't have permission to view this";
    } else if (error.contains('404')) {
      msg = 'This view was not found';
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.warning_amber_rounded,
                size: 64,
                color: Colors.orange.shade400,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              msg,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Please contact your administrator if this issue persists',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Go Back'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.grey.shade700,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: () => setState(() {
                    _dataLoaded = false;
                    _future = context
                        .read<MFilesService>()
                        .fetchObjectsInViewRaw(widget.view.id);
                  }),
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF072F5F),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoMatchesState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.search_off_rounded,
                size: 56,
                color: Colors.blue.shade300,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'No Matches Found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Try adjusting your search',
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => setState(() {
                _filter = '';
                _searchController.clear();
              }),
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear Search'),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF072F5F),
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}