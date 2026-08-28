// ViewDetailsScreen.dart (UPDATED)
// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:mfiles_app/models/group_filter.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/screens/view_items_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/utils/error_messages.dart';
import 'package:mfiles_app/widgets/batch_actions_menu.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
import 'package:mfiles_app/widgets/object_info_dropdown.dart';
import 'package:mfiles_app/widgets/processing_dialog.dart';
import 'package:mfiles_app/widgets/relationships_dropdown.dart';
import 'package:mfiles_app/widgets/version_history_sheet.dart';
import 'package:provider/provider.dart';

import '../models/view_content_item.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import 'package:mfiles_app/widgets/breadcrumb_bar.dart';
import 'package:mfiles_app/widgets/network_banner.dart';
import '../theme/app_colors.dart';
import 'document_preview_screen.dart';
import '../screens/search_results_screen.dart';
import 'package:mfiles_app/utils/delete_object_helper.dart';
import 'package:mfiles_app/utils/snackbar_helper.dart';
import 'package:mfiles_app/widgets/loading_overlay.dart';

enum _SortField {
  name,
  dateCreated,
  lastModified,
  classType,
  objectType,
  displayId,
  id,
  versionId,
}
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

  // ── Multi-selection ────────────────────────────────────────────────

  final Set<int> _selectedIds = {};

  final Map<int, ViewObject> _selectedObjects = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  bool _isSelected(int id) => _selectedIds.contains(id);

  bool _searchWhileSelecting = false;

  bool _isProcessing = false;

  String _processingText = '';

  bool _navLoading = false;
  String? _navMessage;

  _SortField _sortField = _SortField.name;
  bool _sortAscending = true;

  void _setProcessing(bool value, [String text = '']) {
    if (!mounted) return;

    setState(() {
      _isProcessing = value;
      _processingText = text;
    });
  }

  void _selectAll(List<ViewContentItem> items) {
    setState(() {
      _selectedIds.addAll(items.map((item) => item.id));
      _selectedObjects.addEntries(
        items.where((item) => item.id > 0).map(
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

  bool _allSelected(List<ViewContentItem> items) =>
      items.isNotEmpty && _selectedIds.length == items.length;

  void _toggleSelectAll(List<ViewContentItem> items) {
    if (_allSelected(items)) {
      _clearSelection();
    } else {
      _selectAll(items);
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
      _searchWhileSelecting = false;
    });
  }

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

  // Batch delete selected objects
  Future<void> _batchDelete() async {
  if (_selectedObjects.isEmpty) return;

  final confirmed = await showBatchDeleteConfirmDialog(
    context,
    count: _selectedIds.length,
  );

  if (confirmed != true || !mounted) return;

  _setProcessing(true, "Deleting objects...");
  try {
  final svc = context.read<MFilesService>();

  int success = 0;

  for (final obj in _selectedObjects.values) {
    final ok = await svc.deleteObject(
      objectId: obj.id,
      classId: obj.classId,
    );

    if (ok) success++;
  }

    _clearSelection();
    _refreshThisView();

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

  // Batch checkout selected objects
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

  // Batch undo checkout selected objects
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
      if (t.isNotEmpty) return '$t • ID $idPart';
      final c = (item.classTypeName ?? '').trim();
      if (c.isNotEmpty) return '$c • ID $idPart';
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

  List<ViewContentItem> _applySort(List<ViewContentItem> items) {
    final folders = items
        .where((i) => i.isViewFolder || i.isGroupFolder)
        .toList()
      ..sort((a, b) => _alphaCompare(a.title, b.title));

    final objects =
        items.where((i) => !i.isViewFolder && !i.isGroupFolder).toList();

    int compare(ViewContentItem a, ViewContentItem b) {
      switch (_sortField) {
        case _SortField.name:
          return _alphaCompare(a.title, b.title);
        case _SortField.dateCreated:
          return _compareDates(a.createdUtc, b.createdUtc);
        case _SortField.lastModified:
          return _compareDates(a.lastModifiedUtc, b.lastModifiedUtc);
          case _SortField.classType:
        return _compareStrings(a.classTypeName, b.classTypeName);
        case _SortField.displayId:
          return _compareStrings(a.displayId, b.displayId);
        case _SortField.id:
          return _compareInts(a.id, b.id);
        case _SortField.objectType:
          return _compareStrings(a.objectTypeName, b.objectTypeName);
        case _SortField.versionId:
          return _compareInts(a.versionId, b.versionId);
      }
    }

    objects.sort((a, b) => _sortAscending ? compare(a, b) : compare(b, a));

    return [...folders, ...objects];
  }

  int _compareDates(DateTime? a, DateTime? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return a.compareTo(b);
  }

  int _compareStrings(String? a, String? b) {
    final sa = (a ?? '').trim();
    final sb = (b ?? '').trim();
    if (sa.isEmpty && sb.isEmpty) return 0;
    if (sa.isEmpty) return 1;
    if (sb.isEmpty) return -1;
    return _alphaCompare(sa, sb);
  }

  int _compareInts(int a, int b) => a.compareTo(b);

  int _alphaCompare(String a, String b) {
    int category(String s) {
      if (s.isEmpty) return 1; // treat empty as digit-tier, arbitrary but consistent
      final ch = s[0];
      if (RegExp(r'[a-zA-Z]').hasMatch(ch)) return 2;
      if (RegExp(r'[0-9]').hasMatch(ch)) return 1;
      return 0; // symbols/punctuation
    }
    final catA = category(a);
    final catB = category(b);
    if (catA != catB) return catA.compareTo(catB);
    return a.toLowerCase().compareTo(b.toLowerCase());
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
            color: _isSelected(item.id)
            ? AppColors.primary.withOpacity(0.12)
            : infoExpanded
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
                if (_selectionMode && asViewObj != null) {
                  _toggleSelection(asViewObj);
                  return;
                }

                _handleTap(item);
              },
              onLongPress: canDelete
                ? () {
                  debugPrint("LONG PRESS: ${item.title}");
                    if (asViewObj != null) {
                      _toggleSelection(asViewObj);
                    }
                  }
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
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          child: _isSelected(item.id)
                              ? Container(
                                  key: const ValueKey('selected'),
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
                                  child: (item.isObject && svc.isDocumentContentItem(item))
                                      ? FileTypeBadge(
                                          extension: svc.cachedExtensionForObject(item.id) ?? '',
                                          size: 40,
                                        )
                                      : Container(
                                          width: 38,
                                          height: 38,
                                          child: Icon(
                                            isObject ? svc.iconForViewObject(asViewObj!) : Icons.folder_rounded,
                                            color: AppColors.primary,
                                            size: 28,
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
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    height: 1.2,
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
                              padding: const EdgeInsets.all(6),
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
                              padding: const EdgeInsets.all(6),
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

        final looksLikeGuid = propId != null &&
            RegExp(
              r'^\{?[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\}?$',
            ).hasMatch(propId.trim());

        if (propId == null ||
            propId.trim().isEmpty ||
            propDatatype == null ||
            propDatatype.trim().isEmpty ||
            looksLikeGuid) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('This grouping level cannot be opened.')),
          );
          return;
        }

        final svc = context.read<MFilesService>();
        final vid = (item.viewId > 0) ? item.viewId : widget.view.id;

        setState(() {
          _navLoading = true;
          _navMessage = 'Loading ${item.title}...';
        });

        try {
          final items = await svc.fetchViewPropItems(
            viewId: vid,
            filters: [
              GroupFilter(propId: propId, propDatatype: propDatatype)
            ],
          );

          if (mounted) {
            setState(() {
              _navLoading = false;
              _navMessage = null;
            });
          }

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
          if (mounted) {
            setState(() {
              _navLoading = false;
              _navMessage = null;
            });
          }

          if (!context.mounted) return;
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text(humanizeError(e.toString()))));
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
      title: Text(widget.view.name,
          maxLines: 1, overflow: TextOverflow.ellipsis),
      actions: [
        IconButton(
          tooltip: 'Sort',
          icon: Icon(
            Icons.sort_rounded,
            color: (_sortField != _SortField.name || !_sortAscending)
                ? Colors.white
                : Colors.white,
          ),
          onPressed: _showSortSheet,
        ),
        IconButton(
          icon: Icon(_showSearch ? Icons.close : Icons.search),
          onPressed: _toggleSearch,
        ),
        const SizedBox(width: 4),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionAppBar() {
    final svc = context.watch<MFilesService>();
    final allCheckedOut = _selectedObjects.isNotEmpty &&
        _selectedObjects.values.every(
          (obj) => svc.isCheckedOutLocally(obj.id),
        );

    final allNotCheckedOut = _selectedObjects.isNotEmpty &&
        _selectedObjects.values.every(
          (obj) => !svc.isCheckedOutLocally(obj.id),
        );

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

  Widget _buildSelectAllBar(List<ViewContentItem> items) {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          InkWell(
            onTap: () => _toggleSelectAll(items),
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
                      _allSelected(items)
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      key: ValueKey(_allSelected(items)),
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _allSelected(items)
                          ? 'Deselect All'
                          : 'Select All (${items.length})',
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

  @override
  Widget build(BuildContext context) {
    context.watch<MFilesService>();

    return LoadingOverlay(
      isLoading: _navLoading,
      message: _navMessage,
      child: Stack(
        children: [
          PopScope(
          canPop: !_selectionMode,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;

            if (_selectionMode) {
              _clearSelection();
            }
          },
          child: Scaffold(
          backgroundColor: AppColors.surfaceLight,
          appBar: _buildAppBar(),
          body: NetworkBanner(
            child: Column(
              children: [
                _buildBreadcrumbs(),
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
                  final filtered = _applySort(_applyFilter(items));

                  if (items.isEmpty) return _buildEmptyState();
                  if (filtered.isEmpty) return _buildNoMatchesState();

                  return Column(
                    children: [
                      if (_selectionMode) ...[
                        _buildSelectAllBar(items),
                        const SizedBox(height: 2),
                      ],
                      if ((!_selectionMode && _showSearch) || (_selectionMode && _searchWhileSelecting))
                        _buildInViewSearchBar(),
                      Expanded(
                        child: GestureDetector(
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
                    ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      ),
        ),
        if (_isProcessing)
          Positioned.fill(
            child: ColoredBox(
              color: Colors.black45,
              child: Center(
                child: ProcessingDialog(
                  operation: _processingText,
                ),
              ),
            ),
          ),
      ],
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
        padding: const EdgeInsets.all(24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 360),
          padding: const EdgeInsets.fromLTRB(28, 32, 28, 24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.grey.shade100),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.orange.shade100,
                      Colors.orange.shade50,
                    ],
                  ),
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  size: 34,
                  color: Colors.orange.shade600,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                msg,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1A1A1A),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                'Please contact your administrator if this issue persists',
                style: TextStyle(
                  fontSize: 13.5,
                  color: Colors.grey.shade500,
                  height: 1.4,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  onPressed: _refreshThisView,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text(
                    'Try Again',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: TextButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back_rounded,
                      size: 18, color: Colors.grey.shade600),
                  label: Text(
                    'Go Back',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ),
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

  // ───────────────────── SORT SHEET ─────────────────────────────────────────────────────────
  void _showSortSheet() {
    // Each group: field, display label, and whether it currently has a
    // direction selected — used to auto-expand the active group on open.
    final groups = <_SortGroup>[
      _SortGroup('Name', _SortField.name, 'A–Z', 'Z–A'),
      _SortGroup('Date Created', _SortField.dateCreated, 'Oldest first', 'Newest first'),
      _SortGroup('Last Modified', _SortField.lastModified, 'Oldest first', 'Newest first'),
      _SortGroup('Class Type', _SortField.classType, 'A–Z', 'Z–A'),
      _SortGroup('Display ID', _SortField.displayId, 'A–Z', 'Z–A'),
      _SortGroup('ID', _SortField.id, 'Low–High', 'High–Low'),
      _SortGroup('Object Type', _SortField.objectType, 'A–Z', 'Z–A'),
      _SortGroup('Version', _SortField.versionId, 'Low–High', 'High–Low'),
    ];

    // Track expansion state locally; auto-expand whichever group is active.
    final Map<_SortField, bool> expanded = {
      for (final g in groups) g.field: g.field == _sortField,
    };

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        final screenHeight = MediaQuery.of(context).size.height;
        final isShortScreen = screenHeight < 700;

        return DraggableScrollableSheet(
          initialChildSize: isShortScreen ? 0.75 : 0.62,
          minChildSize: isShortScreen ? 0.55 : 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (ctx, setSheet) {
                final screenWidth = MediaQuery.of(ctx).size.width;
                final sheetWidth = screenWidth > 480 ? 480.0 : screenWidth;

                // Find the display label for the currently active sort, for the subtitle.
                final activeGroup = groups.firstWhere((g) => g.field == _sortField);
                final activeLabel = _sortAscending ? activeGroup.ascLabel : activeGroup.descLabel;

                return Center(
                  child: SizedBox(
                    width: sheetWidth,
                    child: Container(
                      decoration: const BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                      ),
                      child: Column(
                        children: [
                          const SizedBox(height: 10),
                          Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                              color: Colors.grey.shade300,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(height: 14),

                          // Teal header, matching filter sheet / vault switcher branding
                          Container(
                            width: double.infinity,
                            margin: const EdgeInsets.symmetric(horizontal: 20),
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(
                                    Icons.sort_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        'Sort By',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${activeGroup.label} · $activeLabel',
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.white70,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white70),
                                  onPressed: () => Navigator.pop(ctx),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 8),

                          Expanded(
                            child: ListView(
                              controller: scrollController,
                              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
                              children: [
                                for (int gi = 0; gi < groups.length; gi++) ...[
                                  _buildSortSectionHeader(
                                    group: groups[gi],
                                    isActive: groups[gi].field == _sortField,
                                    activeLabel: groups[gi].field == _sortField ? activeLabel : null,
                                    expanded: expanded[groups[gi].field]!,
                                    onToggle: () => setSheet(
                                      () => expanded[groups[gi].field] =
                                          !expanded[groups[gi].field]!,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  AnimatedSize(
                                    duration: const Duration(milliseconds: 200),
                                    curve: Curves.easeInOut,
                                    alignment: Alignment.topCenter,
                                    child: expanded[groups[gi].field]!
                                        ? Container(
                                            decoration: BoxDecoration(
                                              color: Colors.grey.shade50,
                                              borderRadius: BorderRadius.circular(14),
                                              border: Border.all(color: Colors.grey.shade200),
                                            ),
                                            child: Column(
                                              children: [
                                                _buildSortRow(
                                                  label: groups[gi].ascLabel,
                                                  selected: _sortField == groups[gi].field &&
                                                      _sortAscending == true,
                                                  onTap: () {
                                                    setState(() {
                                                      _sortField = groups[gi].field;
                                                      _sortAscending = true;
                                                    });
                                                    Navigator.pop(ctx);
                                                  },
                                                ),
                                                Divider(height: 1, color: Colors.grey.shade200, indent: 16),
                                                _buildSortRow(
                                                  label: groups[gi].descLabel,
                                                  selected: _sortField == groups[gi].field &&
                                                      _sortAscending == false,
                                                  onTap: () {
                                                    setState(() {
                                                      _sortField = groups[gi].field;
                                                      _sortAscending = false;
                                                    });
                                                    Navigator.pop(ctx);
                                                  },
                                                ),
                                              ],
                                            ),
                                          )
                                        : const SizedBox.shrink(),
                                  ),
                                  if (gi != groups.length - 1) const SizedBox(height: 16),
                                ],
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildSortSectionHeader({
    required _SortGroup group,
    required bool isActive,
    required String? activeLabel,
    required bool expanded,
    required VoidCallback onToggle,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
          child: Row(
            children: [
              Text(
                group.label.toUpperCase(),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.5,
                  color: Colors.grey.shade500,
                ),
              ),
              if (isActive) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    activeLabel ?? '',
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary,
                    ),
                  ),
                ),
              ],
              const Spacer(),
              Icon(
                expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                size: 20,
                color: Colors.grey.shade500,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSortRow({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? AppColors.primary : const Color(0xFF1E293B),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              selected
                  ? const Icon(Icons.check_rounded, size: 20, color: AppColors.primary)
                  : const SizedBox(width: 20),
            ],
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

// ───────────────────── SORT GROUP CLASS ─────────────────────────────────────────────────────────
class _SortGroup {
  final String label;
  final _SortField field;
  final String ascLabel;
  final String descLabel;

  const _SortGroup(this.label, this.field, this.ascLabel, this.descLabel);
}