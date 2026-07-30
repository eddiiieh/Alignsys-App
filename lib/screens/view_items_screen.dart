import 'package:flutter/material.dart';
import 'package:mfiles_app/models/group_filter.dart';
import 'package:mfiles_app/widgets/batch_actions_menu.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
import 'package:mfiles_app/widgets/object_info_dropdown.dart';
import 'package:mfiles_app/widgets/processing_dialog.dart';
import 'package:mfiles_app/widgets/version_history_sheet.dart';
import 'package:provider/provider.dart';

import '../models/view_content_item.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import '../services/mfiles_service.dart';
import 'object_details_screen.dart';
import 'view_details_screen.dart';
import '../widgets/relationships_dropdown.dart';
import 'package:mfiles_app/widgets/breadcrumb_bar.dart';

import 'package:mfiles_app/widgets/network_banner.dart';
import '../theme/app_colors.dart';

import '../screens/document_preview_screen.dart';
import '../screens/search_results_screen.dart';

import 'package:mfiles_app/utils/delete_object_helper.dart';
import 'package:mfiles_app/utils/snackbar_helper.dart';

class ViewItemsScreen extends StatefulWidget {
  final String title;
  final int parentViewId;
  final List<ViewContentItem> items;
  final List<GroupFilter> filters;
  final String? parentViewName;
  final String? parentSection;

  const ViewItemsScreen({
    super.key,
    required this.title,
    required this.parentViewId,
    required this.items,
    required this.filters,
    this.parentViewName,
    this.parentSection,
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

  final Set<int> _previewLoading = {};

  int? _expandedInfoItemId;
  int? _expandedRelationshipsItemId;

  // ── Multi-selection ─────────────────────────────────────────────

  final Set<int> _selectedIds = {};
  final Map<int, ViewObject> _selectedObjects = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  bool _isSelected(int id) => _selectedIds.contains(id);

  bool _searchWhileSelecting = false;

  bool _isProcessing = false;

  String _processingText = '';

  void _setProcessing(bool value, [String text = '']) {
    if (!mounted) return;

    setState(() {
      _isProcessing = value;
      _processingText = text;
    });
  }

  void _selectAll() {
    setState(() {
      _selectedIds.addAll(_items.map((item) => item.id));
      _selectedObjects.addEntries(
        _items.where((item) => item.id > 0).map(
          (item) => MapEntry(
            item.id,
            ViewObject(
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
            ),
          ),
        ),
      );
    });
  }

  bool get _allSelected =>
      _items.isNotEmpty && _selectedIds.length == _items.length;

  void _toggleSelectAll() {
    if (_allSelected) {
      _clearSelection();
    } else {
      _selectAll();
    }
  }

  void _toggleSelection(ViewObject obj) {
    setState(() {
      if (_selectedIds.remove(obj.id)) {
        _selectedObjects.remove(obj.id);
      } else {
        _selectedIds.add(obj.id);
        _selectedObjects[obj.id] = obj;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectedObjects.clear();
      _expandedInfoItemId = null;
      _expandedRelationshipsItemId = null;
      _searchWhileSelecting = false;
    });
  }

  Future<void> _batchCheckout() async {
    if (_selectedObjects.isEmpty) return;

    _setProcessing(true, "Checking out documents...");
    try {

    final service = context.read<MFilesService>();

    int success = 0;

    for (final obj in _selectedObjects.values) {
      final checkedOut = await service.checkoutObject(
        objectId: obj.id,
        objectTypeId: obj.objectTypeId,
      );

      if (checkedOut) {
        success++;
      }
    }

    _clearSelection();

    if (!mounted) return;

    SnackbarHelper.showSuccess(
      context,
      success == 1
          ? '1 object checked out'
          : '$success objects checked out',
    );
  } finally {
      _setProcessing(false);
    }
  }

  Future<void> _batchUndoCheckout() async {
    if (_selectedObjects.isEmpty) return;

    _setProcessing(true, "Checking in documents...");
    try {

    final service = context.read<MFilesService>();

    int success = 0;

    for (final obj in _selectedObjects.values) {
      final checkedIn = await service.undoCheckoutObject(
        objectId: obj.id,
        objectTypeId: obj.objectTypeId,
      );

      if (checkedIn) {
        success++;
      }
    }

    _clearSelection();

    if (!mounted) return;

    SnackbarHelper.showSuccess(
      context,
      success == 1
          ? '1 object checked in'
          : '$success objects checked in',
    );
  } finally {
      _setProcessing(false);
    }
  }

  Future<void> _batchDelete() async {
    if (_selectedObjects.isEmpty) return;

    _setProcessing(true, "Deleting objects...");
    try {

    final confirmed = await showBatchDeleteConfirmDialog(
      context,
      count: _selectedIds.length,
    );

    if (confirmed != true || !mounted) return;

    final svc = context.read<MFilesService>();

    int success = 0;

    for (final obj in _selectedObjects.values) {
      final ok = await svc.deleteObject(
        objectId: obj.id,
        classId: obj.classId,
      );

      if (ok) success++;
    }

    setState(() {
      _items.removeWhere((e) => _selectedIds.contains(e.id));
    });

    _clearSelection();

    if (!mounted) return;

    SnackbarHelper.showSuccess(
      context,
      success == 1
          ? '1 object deleted'
          : '$success objects deleted',
    );
  } finally {
      _setProcessing(false);
    }
  }

  // ✅ Unified icon-tap claim: timestamp-based, set synchronously.
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
    // Clear after the gesture arena has fully resolved.
    Future.delayed(const Duration(milliseconds: 100), () {
      if (mounted) _suppressRowTap = false;
    });
    return true;
  }

  @override
  void initState() {
    super.initState();
    _items = widget.items;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final svc = context.read<MFilesService>();
      svc.warmExtensionsForItems(_items);
      svc.syncCheckoutStateForItems(_items);
    });
  }

  @override
  void didUpdateWidget(covariant ViewItemsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items != widget.items) {
      _items = widget.items;
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

  // ─── NEW: navigate to the document preview screen ───────────────────────
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
      final displayIdInt =
          int.tryParse(item.displayId?.trim() ?? '') ?? item.id;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => DocumentPreviewScreen(
                displayObjectId: displayIdInt,
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
  // ────────────────────────────────────────────────────────────────────────

  String? _subtitleLabel(ViewContentItem item) {
    if (item.isObject) {
      final idPart =
          (item.displayId ?? '').trim().isNotEmpty
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
    final segments = <BreadcrumbSegment>[
      BreadcrumbSegment(
        label: 'Home',
        icon: Icons.home_rounded,
        onTap: () => Navigator.popUntil(context, (route) => route.isFirst),
      ),
    ];

    if (widget.parentViewName != null) {
      segments.add(
        BreadcrumbSegment(
          label: widget.parentViewName!,
          onTap: () => Navigator.pop(context),
        ),
      );
    }

    segments.add(BreadcrumbSegment(label: widget.title));
    return BreadcrumbBar(segments: segments);
  }

  Widget _buildRow(ViewContentItem item, bool isLast) {
    final subtitle = _subtitleLabel(item);
    final svc = context.watch<MFilesService>();

    final bool isObject = item.isObject && item.id > 0;
    final bool hasRelationships = isObject && item.classId > 0;

    // ─── NEW: only show the eye icon for document-type objects ──────────
    final bool isDocument = isObject && svc.isDocumentContentItem(item);
    // ────────────────────────────────────────────────────────────────────

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

    final bool infoExpanded = _expandedInfoItemId == item.id;
    final bool relationshipsExpanded = _expandedRelationshipsItemId == item.id;

    final bool isDimmed = _expandedInfoItemId != null && !infoExpanded;

    final BorderRadius radius =
        isLast
            ? const BorderRadius.vertical(bottom: Radius.circular(12))
            : BorderRadius.zero;

    final ViewObject asViewObj = ViewObject(
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

    // ✅ TapRegion removed — see ViewDetailsScreen for full explanation.
    return Column(
      children: [
        AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isDimmed ? 0.45 : 1.0,
          child: Material(
            color:
                _isSelected(item.id)
                    ? AppColors.primary.withValues(alpha: 0.12)
                    : infoExpanded
                    ? AppColors.primary.withValues(alpha: 0.03)
                    : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: radius,
              side:
                  infoExpanded
                      ? const BorderSide(color: AppColors.primary, width: 1.5)
                      : BorderSide.none,
            ),
            clipBehavior: Clip.antiAlias,
            elevation: 0,
            child: InkWell(
              borderRadius: radius,
              onLongPress: () {
                _toggleSelection(asViewObj);
              },
              onTap: () {
                // ✅ Guard: reject if an icon tap was just claimed.
                final now = DateTime.now();
                if (_suppressRowTap) return;
                if (_lastIconTap != null &&
                    now.difference(_lastIconTap!) <
                        const Duration(milliseconds: 350))
                  return;

                if (isDimmed) {
                  setState(() {
                    _expandedInfoItemId = null;
                    _expandedRelationshipsItemId = null;
                  });
                  return;
                }

                if (_selectionMode) {
                  _toggleSelection(asViewObj);
                  return;
                }

                _handleTap(item);
              },
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        // ✅ Relationships chevron
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

                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child:
                              _isSelected(item.id)
                                  ? Container(
                                    width: 38,
                                    height: 38,
                                    decoration: const BoxDecoration(
                                      color: AppColors.primary,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.check,
                                      color: Colors.white,
                                      size: 22,
                                    ),
                                  )
                                  : _CheckoutBadge(
                                    objectId: item.id,
                                    child:
                                        (item.isObject &&
                                                svc.isDocumentContentItem(item))
                                            ? FileTypeBadge(
                                              extension:
                                                  svc.cachedExtensionForObject(
                                                    item.id,
                                                  ) ??
                                                  '',
                                              size: 40,
                                            )
                                            : Container(
                                              width: 38,
                                              height: 38,
                                              decoration: BoxDecoration(
                                                color: AppColors.primary
                                                    .withOpacity(0.10),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                              ),
                                              child: const Icon(
                                                Icons.folder_rounded,
                                                color: AppColors.primary,
                                                size: 20,
                                              ),
                                            ),
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

                        // ─── NEW: Eye / preview icon (documents only) ────────────
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
                              child:
                                  _previewLoading.contains(
                                        item.id,
                                      ) // ← add spinner
                                      ? SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                                Colors.blueGrey.shade400,
                                              ),
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
                        // ─────────────────────────────────────────────────────────

                        // ✅ Info icon
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
                                color:
                                    infoExpanded
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
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.grey.shade400,
                          ),
                      ],
                    ),
                  ),

                  if (infoExpanded && isObject) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    ObjectInfoDropdown(obj: asViewObj),
                  ],

                  if (relationshipsExpanded && hasRelationships) ...[
                    Divider(height: 1, color: Colors.grey.shade200),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                      child: RelationshipsDropdown(
                        key: ValueKey('rel_${item.id}'),
                        obj: asViewObj,
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
        isSingleFile: item.isSingleFile,
        isCheckedOut: item.isCheckedOut,
        checkoutUserId: item.checkoutUserId,
        checkoutUsername: item.checkoutUsername,
      );

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ObjectDetailsScreen(
                obj: obj,
                parentViewName: widget.parentViewName,
                parentSection: widget.parentSection,
                groupingName: widget.title,
              ),
        ),
      );
      return;
    }

    if (item.isViewFolder) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ViewDetailsScreen(
                view: ViewItem(id: item.id, name: item.title, count: 0),
                parentSection: widget.parentSection,
              ),
        ),
      );
      return;
    }

    if (item.isGroupFolder) {
      String key = item.propId?.trim() ?? '';
      String dtype = item.propDatatype?.trim() ?? '';

      final looksLikeGuid = RegExp(
        r'^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$',
      ).hasMatch(key);

      if (key.isEmpty || dtype.isEmpty || looksLikeGuid) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('This grouping level cannot be opened.')),
        );
        return;
      }

      final isTwoDigitMonth = RegExp(r'^(0[1-9]|1[0-2])$').hasMatch(key);
      if (isTwoDigitMonth) dtype = 'MFDatatypeText';

      final svc = context.read<MFilesService>();
      final vid = (item.viewId > 0) ? item.viewId : widget.parentViewId;

      final nextFilters = <GroupFilter>[
        ...widget.filters,
        GroupFilter(propId: key, propDatatype: dtype),
      ];

      List<ViewContentItem> children;
      try {
        children = await svc.fetchViewPropItems(
          viewId: vid,
          filters: nextFilters,
        );
      } catch (e) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load items: $e')),
        );
        return;
      }

      if (!context.mounted) return;

      context.read<MFilesService>().warmExtensionsForItems(children);

      Navigator.push(
        context,
        MaterialPageRoute(
          builder:
              (_) => ViewItemsScreen(
                title: item.title,
                parentViewId: vid,
                items: children,
                filters: nextFilters,
                parentViewName: widget.title,
                parentSection: widget.parentSection,
              ),
        ),
      );
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Unsupported item type')));
  }

  PreferredSizeWidget _buildAppBar() {
    if (!_selectionMode) {
      return _buildNormalAppBar();
    }

    return _buildSelectionAppBar();
  }

  PreferredSizeWidget _buildNormalAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 12,
      title: Text(
        widget.title,
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
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final allCheckedOut =
        _selectedObjects.values.every((o) => o.isCheckedOut);

    final allNotCheckedOut =
        _selectedObjects.values.every((o) => !o.isCheckedOut);

    return AppBar(
      backgroundColor: AppColors.primary,
      foregroundColor: Colors.white,
      elevation: 0,
      toolbarHeight: 64,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () {
          if (_searchWhileSelecting) {
            setState(() {
              _searchWhileSelecting = false;
              _filter = '';
              _searchController.clear();
            });
          } else {
            _clearSelection();
          }
        },
      ),
      title: Text(
        '${_selectedIds.length} selected',
        style: const TextStyle(
          fontWeight: FontWeight.w600,
        ),
      ),
      actions: [
        IconButton(
          tooltip: 'Search',
          icon: const Icon(Icons.search),
          onPressed: () {
            setState(() {
              _searchWhileSelecting = true;
            });
          },
        ),
        if (allNotCheckedOut)
          IconButton(
            tooltip: 'Checkout',
            icon: const Icon(Icons.lock_open),
            onPressed: _batchCheckout,
          ),
        if (allCheckedOut)
          IconButton(
            tooltip: 'Check In',
            icon: const Icon(Icons.lock),
            onPressed: _batchUndoCheckout,
          ),
        IconButton(
          tooltip: 'Delete',
          icon: const Icon(Icons.delete_outline),
          onPressed: _batchDelete,
        ),
        BatchActionsMenu(
          onSelected: (value) async {
            switch (value) {
              case 'history':
                if (_selectedObjects.length == 1) {
                  final obj = _selectedObjects.values.first;
                  _clearSelection();
                  showVersionHistorySheet(
                    context,
                    obj: obj,
                    onRolledBack: () {
                    },
                  );
                }
                break;

              case 'download':
                _setProcessing(true, "Downloading files...");
                try {
                  final svc = context.read<MFilesService>();

                  int success = 0;
                  String? lastPath;

                  for (final obj in _selectedObjects.values) {
                    try {
                      final files = await svc.fetchObjectFiles(
                        objectId: obj.id,
                        classId: obj.classId,
                      );

                      if (files.isEmpty) continue;

                      final file = files.first;

                      lastPath = await svc.downloadAndSaveFile(
                        displayObjectId: obj.id,
                        classId: obj.classId,
                        fileId: file.fileId,
                        reportGuid: file.reportGuid,
                        fileTitle: file.fileTitle,
                        extension: file.extension,
                      );

                      success++;
                    } catch (e) {
                      debugPrint(e.toString());
                    }
                  }

                  if (!mounted) return;

                  if (success == 1 && lastPath != null) {
                    SnackbarHelper.showSuccess(context, 'Downloaded to: $lastPath');
                  } else if (success > 1 && lastPath != null) {
                    final folder = lastPath.substring(0, lastPath.lastIndexOf('/'));
                    SnackbarHelper.showSuccess(
                      context,
                      'Downloaded $success files to: $folder',
                    );
                  } else {
                    SnackbarHelper.showSuccess(context, 'Downloaded $success files');
                  }

                  _clearSelection();
                } finally {
                  _setProcessing(false);
                }

                break;

              case 'convertPdf':
              _setProcessing(true, "Converting to PDF...");
              try {
                final svc = context.read<MFilesService>();

                int converted = 0;

                for (final obj in _selectedObjects.values) {
                  try {
                    final files = await svc.fetchObjectFiles(
                      objectId: obj.id,
                      classId: obj.classId,
                    );

                    if (files.isEmpty) continue;

                    await svc.convertToPdf(
                      objectId: obj.id,
                      classId: obj.classId,
                      fileId: files.first.fileId,
                      overWriteOriginal: false,
                      separateFile: true,
                    );

                    converted++;
                  } catch (e) {
                    debugPrint(e.toString());
                  }
                }

                if (!mounted) return;

                SnackbarHelper.showSuccess(
                  context,
                  'Converted $converted ${converted == 1 ? "document" : "documents"} to PDF',
                );
                _clearSelection();
              } finally {
                _setProcessing(false); 
              }

              break;
            }
          },
        ),
      ],
    );
  }

  Widget _buildSelectAllBar() {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          InkWell(
            onTap: _toggleSelectAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 14,
              ),
              child: Row(
                children: [
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Icon(
                      _allSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      key: ValueKey(_allSelected),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _allSelected
                          ? 'Deselect All'
                          : 'Select All (${_items.length})',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            color: Colors.grey.shade200,
          ),
        ],
      ),
    );
  }

  Widget _buildSelectionSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 10,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade300,
          ),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.check_circle,
            color: AppColors.primary,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${_selectedIds.length} items selected',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _applyFilter(_items);

    return Stack(
      children: [
        Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: _buildAppBar(),
      body: NetworkBanner(
        child: Column(
          children: [
            if (_selectionMode) ...[
              _buildSelectAllBar(),
              const SizedBox(height: 2),
            ],
            if (!_selectionMode || !_searchWhileSelecting)
              _buildBreadcrumbs(),
            if ((!_selectionMode && _showSearch) || (_selectionMode && _searchWhileSelecting))
              _buildSearchBar(),
            Expanded(
              child:
                  filtered.isEmpty
                      ? const Center(child: Text('No items found'))
                      // ✅ Dismiss expanded dropdowns when tapping empty list space.
                      : GestureDetector(
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
                        child: Scrollbar(
                          controller: _itemsScroll,
                          interactive: true,
                          thickness: 6,
                          radius: const Radius.circular(8),
                          child: ListView(
                            controller: _itemsScroll,
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.all(10),
                            children: [
                              Container(
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.grey.shade100,
                                    width: 0.5,
                                  ),
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
                                    (i) => _buildRow(
                                      filtered[i],
                                      i == filtered.length - 1,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ), // Scrollbar
                      ), // GestureDetector
            ),
          ],
        ),
      ),
      ),
      if (_isProcessing)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black45,
              child: Center(
                child: ProcessingDialog(operation: _processingText),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildSearchBar() {
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
            // Only navigate to SearchResultsScreen in normal mode
            if (!_selectionMode) {
              await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => SearchResultsScreen(initialQuery: ''),
                ),
              );
            }
          },
          child: AbsorbPointer(
            absorbing: !_selectionMode,
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
                suffixIcon:
                    _filter.isNotEmpty
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
