// ViewDetailsScreen.dart (UPDATED)
// ignore_for_file: use_build_context_synchronously, deprecated_member_use

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
import 'package:mfiles_app/widgets/network_banner.dart';
import '../theme/app_colors.dart';
import 'document_preview_screen.dart';
import '../screens/search_results_screen.dart';

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

  // ── per-item preview-loading set ──────────────────────────────────────────
  final Set<int> _previewLoading = {};

  bool _suppressRowTap = false;
  DateTime? _lastIconTap;

  bool _tryClaimIconTap() {
    final now = DateTime.now();
    if (_lastIconTap != null &&
        now.difference(_lastIconTap!) < const Duration(milliseconds: 350)) {
      return false;
    }
    _lastIconTap = now;
    _suppressRowTap = true;
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _suppressRowTap = false;
    });
    return true;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dataLoaded) {
      _dataLoaded = true;
      _future = context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id).then((items) {
        final svc = context.read<MFilesService>();
        svc.warmExtensionsForItems(items);
        svc.syncCheckoutStateForItems(items);   // ← ADD
        return items;
      });
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
      _expandedInfoItemId = null;
      _expandedRelationshipsItemId = null;
      _future =
          context.read<MFilesService>().fetchObjectsInViewRaw(widget.view.id).then((items) {
        final svc = context.read<MFilesService>();
        svc.warmExtensionsForItems(items);
        svc.syncCheckoutStateForItems(items);
        return items;
      });
    });
  }

  void _toggleInfo(int itemId) {
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
    setState(() {
      if (_expandedRelationshipsItemId == itemId) {
        _expandedRelationshipsItemId = null;
      } else {
        _expandedRelationshipsItemId = itemId;
        _expandedInfoItemId = null;
      }
    });
  }

  // ── Fetch files first, then push DocumentPreviewScreen ────────────────────
  Future<void> _openPreview(ViewContentItem item) async {
    if (!_tryClaimIconTap()) return;
    if (_previewLoading.contains(item.id)) return;

    setState(() => _previewLoading.add(item.id));
    try {
      final svc = context.read<MFilesService>();
      final files = await svc.fetchObjectFiles(
        objectId: item.id,
        classId: item.classId,
      );

      if (!mounted) return;

      if (files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No files attached to this document.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      final f = files.first;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => DocumentPreviewScreen(
            displayObjectId: item.id,
            classId: item.classId,
            fileId: f.fileId,
            fileTitle: f.fileTitle,
            extension: f.extension,
            reportGuid: f.reportGuid,
            objectTypeId: item.objectTypeId,
            canDownload: true,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to load preview: $e'),
          backgroundColor: Colors.red.shade600,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _previewLoading.remove(item.id));
    }
  }

  String? _subtitleLabel(ViewContentItem item) {
    if (item.isObject) {
      final idPart = (item.displayId ?? '').trim().isNotEmpty
          ? item.displayId!.trim()
          : '${item.id}';
      final t = (item.objectTypeName ?? '').trim();
      if (t.isNotEmpty) return '$t | ID $idPart';
      final c = (item.classTypeName ?? '').trim();
      if (c.isNotEmpty) return '$c | ID $idPart';
      return 'ID $idPart';
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: GestureDetector(
          onTap: () async {
            await Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SearchResultsScreen(initialQuery: ''),
              ),
            );
          },
          child: AbsorbPointer(
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search repository...',
                hintStyle: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                  fontWeight: FontWeight.w400,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 14,
                  horizontal: 16,
                ),
                prefixIcon: Icon(
                  Icons.search_rounded,
                  color: AppColors.primary.withOpacity(0.6),
                  size: 20,
                ),
                suffixIcon: _filter.isNotEmpty
                    ? IconButton(
                        icon: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Colors.grey.shade400,
                        ),
                        onPressed: () {
                          setState(() {
                            _filter = '';
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _filter = v),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRow(ViewContentItem item, bool isLast) {
    final subtitle = _subtitleLabel(item);
    final svc = context.watch<MFilesService>();

    final bool isObject = item.isObject && item.id > 0;
    final bool hasRelationships = isObject && item.classId > 0;
    final bool canDelete = isObject;
    final bool isDocument = isObject && svc.isDocumentContentItem(item);

    final bool infoExpanded = _expandedInfoItemId == item.id;
    final bool relationshipsExpanded = _expandedRelationshipsItemId == item.id;
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
            isSingleFile: item.isSingleFile,
            isCheckedOut: item.isCheckedOut,
            checkoutUserId: item.checkoutUserId,
            checkoutUsername: item.checkoutUsername,
          )
        : null;

    if (hasRelationships && svc.cachedHasRelationships(item.id) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          svc.ensureRelationshipsPresenceForObject(
            objectId: item.id,
            objectTypeId: item.objectTypeId,
            classId: item.classId,
            notify: true,
          );
        }
      });
    }

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
                ? AppColors.primary.withOpacity(0.03)
                : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side: infoExpanded
                  ? const BorderSide(color: AppColors.primary, width: 1.5)
                  : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: InkWell(
              borderRadius: radius,
              onTap: () {
                final now = DateTime.now();
                if (_suppressRowTap) return;
                if (_lastIconTap != null &&
                    now.difference(_lastIconTap!) <
                        const Duration(milliseconds: 350)) return;
                if (isDimmed) {
                  setState(() {
                    _expandedInfoItemId = null;
                    _expandedRelationshipsItemId = null;
                  });
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
                        if (hasRelationships &&
                            svc.cachedHasRelationships(item.id) == true) ...[
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (!_tryClaimIconTap()) return;
                              _toggleRelationships(item.id);
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(4),
                              child: Icon(
                                relationshipsExpanded
                                    ? Icons.expand_more
                                    : Icons.chevron_right,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ] else
                          const SizedBox(width: 4),

                        // Badge / folder
                        _CheckoutBadge(
                          objectId: item.id,
                          child: (item.isObject && svc.isDocumentContentItem(item))
                              ? FileTypeBadge(
                                  extension:
                                      svc.cachedExtensionForObject(item.id) ?? '',
                                  size: 40,
                                )
                              : Container(
                                  width: 38,
                                  height: 38,
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withOpacity(0.10),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.folder_rounded,
                                      color: AppColors.primary, size: 20),
                                ),
                        ),

                        const SizedBox(width: 10),

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
                                    fontWeight: FontWeight.w600),
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
                                      color: Colors.grey.shade600),
                                ),
                              ],
                            ],
                          ),
                        ),

                        // ── Eye icon (documents only) ──────────────────
                        if (isDocument) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () => _openPreview(item),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: _previewLoading.contains(item.id)
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        valueColor:
                                            AlwaysStoppedAnimation<Color>(
                                                Colors.blueGrey.shade400),
                                      ),
                                    )
                                  : Icon(
                                      Icons.remove_red_eye_outlined,
                                      size: 18,
                                      color: Colors.blueGrey.shade400,
                                    ),
                            ),
                          ),
                        ],

                        // Info icon
                        if (isObject) ...[
                          const SizedBox(width: 6),
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              if (!_tryClaimIconTap()) return;
                              _toggleInfo(item.id);
                            },
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: infoExpanded
                                    ? AppColors.primary.withOpacity(0.15)
                                    : AppColors.primary.withOpacity(0.08),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                infoExpanded
                                    ? Icons.keyboard_arrow_up_rounded
                                    : Icons.info_outline,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ] else
                          Icon(Icons.chevron_right_rounded,
                              size: 18, color: Colors.grey.shade400),
                      ],
                    ),
                  ),

                  if (infoExpanded && isObject) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    ObjectInfoDropdown(obj: asViewObj!),
                  ],

                  if (relationshipsExpanded && hasRelationships) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: RelationshipsDropdown(
                        key: ValueKey('rel_${item.id}'),
                        obj: asViewObj!,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (!isLast)
          Divider(height: 0.5, thickness: 0.5, color: Colors.grey.shade100),
      ],
    );
  }

  Future<void> _handleTap(ViewContentItem item) async {
    if (!item.isObject) {
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
            const SnackBar(
                content: Text('There are no items in this view.')),
          );
          return;
        }

        final svc = context.read<MFilesService>();
        final vid = (item.viewId > 0) ? item.viewId : widget.view.id;

        try {
          final items = await svc.fetchViewPropItems(
            viewId: vid,
            filters: [
              GroupFilter(propId: propId, propDatatype: propDatatype)
            ],
          );
          if (!context.mounted) return;
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ViewItemsScreen(
                title: item.title,
                items: items,
                parentViewId: vid,
                filters: [
                  GroupFilter(propId: propId, propDatatype: propDatatype)
                ],
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
      return;
    }

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
      isSingleFile: item.isSingleFile,
      isCheckedOut: item.isCheckedOut,
      checkoutUserId: item.checkoutUserId,
      checkoutUsername: item.checkoutUsername,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 12,
        title: Text(widget.view.name,
            maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.close : Icons.search),
            onPressed: _toggleSearch,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: NetworkBanner(
        child: Column(
          children: [
            _buildBreadcrumbs(),
            if (_showSearch) _buildInViewSearchBar(),
            Expanded(
              child: FutureBuilder<List<ViewContentItem>>(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator());
                  }

                  if (snap.hasError) {
                    final error = snap.error.toString();
                    final isEmpty = error.contains('400') ||
                        error.contains(
                            'cannot be used to define a grouping level') ||
                        error.contains('Unspecified error') ||
                        error.contains('No items') ||
                        error.contains('empty');
                    return isEmpty
                        ? _buildEmptyState()
                        : _buildErrorState(error);
                  }

                  final items = snap.data ?? [];
                  final filtered = _applyFilter(items);

                  if (items.isEmpty) return _buildEmptyState();
                  if (filtered.isEmpty) return _buildNoMatchesState();

                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onTap: () {
                      if (_expandedInfoItemId != null ||
                          _expandedRelationshipsItemId != null) {
                        setState(() {
                          _expandedInfoItemId = null;
                          _expandedRelationshipsItemId = null;
                        });
                      }
                    },
                    child: RefreshIndicator(
                      onRefresh: () async {
                        _refreshThisView();
                        await _future;
                      },
                      child: Scrollbar(
                        controller: _viewScroll,
                        interactive: true,
                        thickness: 6,
                        radius: const Radius.circular(8),
                        child: ListView(
                          controller: _viewScroll,
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(8),
                          children: [
                            Container(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: Colors.grey.shade100, width: 0.5),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.04),
                                    blurRadius: 12,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Column(
                                children: List.generate(
                                  filtered.length,
                                  (i) => _buildRow(filtered[i],
                                      i == filtered.length - 1),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

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
                  color: Colors.grey.shade100, shape: BoxShape.circle),
              child: Icon(Icons.inbox_outlined,
                  size: 64, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            Text('No Items Found',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Text('This view is currently empty',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: _refreshThisView,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(
                    color: AppColors.primary.withOpacity(0.3)),
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
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
                  color: Colors.orange.shade50, shape: BoxShape.circle),
              child: Icon(Icons.warning_amber_rounded,
                  size: 64, color: Colors.orange.shade400),
            ),
            const SizedBox(height: 24),
            Text(msg,
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
                'Please contact your administrator if this issue persists',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
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
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
                const SizedBox(width: 12),
                ElevatedButton.icon(
                  onPressed: _refreshThisView,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Try Again'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
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
                  color: Colors.blue.shade50, shape: BoxShape.circle),
              child: Icon(Icons.search_off_rounded,
                  size: 56, color: Colors.blue.shade300),
            ),
            const SizedBox(height: 20),
            Text('No Matches Found',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800)),
            const SizedBox(height: 8),
            Text('Try adjusting your search',
                style: TextStyle(
                    fontSize: 14, color: Colors.grey.shade600)),
            const SizedBox(height: 20),
            TextButton.icon(
              onPressed: () => setState(() {
                _filter = '';
                _searchController.clear();
              }),
              icon: const Icon(Icons.clear_rounded, size: 18),
              label: const Text('Clear Search'),
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 20, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────── CHECKOUT BADGE CLASS ─────────────────────────────────────────────────────────
class _CheckoutBadge extends StatelessWidget {
  final int objectId;
  final Widget child;

  const _CheckoutBadge({required this.objectId, required this.child});

  @override
  Widget build(BuildContext context) {
    final isOut = context.watch<MFilesService>().isCheckedOutLocally(objectId);
    if (!isOut) return child;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 16,
            height: 16,
            decoration: const BoxDecoration(
              color: Color(0xFF0F766E),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.drive_file_rename_outline,
              size: 10,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }
}