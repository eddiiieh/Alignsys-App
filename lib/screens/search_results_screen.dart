import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/document_preview_screen.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/widgets/batch_actions_menu.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
import 'package:mfiles_app/widgets/network_banner.dart';
import 'package:mfiles_app/widgets/object_info_dropdown.dart';
import 'package:mfiles_app/widgets/processing_dialog.dart';
import 'package:mfiles_app/widgets/relationships_dropdown.dart';
import 'package:mfiles_app/widgets/version_history_sheet.dart';
import 'package:provider/provider.dart';

import '../models/view_object.dart';
import '../theme/app_colors.dart';

import 'package:mfiles_app/utils/delete_object_helper.dart';
import 'package:mfiles_app/utils/snackbar_helper.dart';

class SearchResultsScreen extends StatefulWidget {
  final String initialQuery;

  const SearchResultsScreen({super.key, required this.initialQuery});

  @override
  State<SearchResultsScreen> createState() => _SearchResultsScreenState();
}

class _SearchResultsScreenState extends State<SearchResultsScreen> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  Timer? _debounce;

  // States
  bool _isSearching = false;
  bool _hasSearched = false;
  String _lastQuery = '';
  List<ViewObject> _results = [];
  String? _errorMessage;
  bool _isWarming = false;

  int? _expandedInfoItemId;
  int? _expandedRelationshipsItemId;

  final Set<int> _previewLoading = {};

  final ScrollController _scrollController = ScrollController();

  final Set<int> _selectedIds = {};
  final Map<int, ViewObject> _selectedObjects = {};

  bool get _selectionMode => _selectedIds.isNotEmpty;

  bool _isSelected(int id) => _selectedIds.contains(id);

  bool _searchWhileSelecting = false;

  bool _showSelectedOnly = false;

  // Advanced filter state
  final Set<int> _selectedObjectTypeIds = {};
  int? _selectedClassId;

  bool get _hasActiveFilters =>
      _selectedObjectTypeIds.isNotEmpty || _selectedClassId != null;

  bool _isProcessing = false;

  String _processingText = '';

  void _setProcessing(bool value, [String text = '']) {
    if (!mounted) return;

    setState(() {
      _isProcessing = value;
      _processingText = text;
    });
  }

  void _toggleSelection(ViewObject obj) {
    setState(() {
      if (_selectedIds.remove(obj.id)) {
        _selectedObjects.remove(obj.id);
      } else {
        _selectedIds.add(obj.id);
        _selectedObjects[obj.id] = obj;
      }
      if (_selectedIds.isEmpty) {
        _showSelectedOnly = false;
        _searchWhileSelecting = false;
      }
    });
  }

  void _clearSelection() {
    setState(() {
      _selectedIds.clear();
      _selectedObjects.clear();
      _showSelectedOnly = false;
      _searchWhileSelecting = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();

    if (widget.initialQuery.trim().isNotEmpty) {
      _lastQuery = widget.initialQuery.trim();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _runSearch(widget.initialQuery.trim());
        _focusNode.requestFocus();
      });
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusNode.requestFocus());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    final trimmed = value.trim();

    if (trimmed.isEmpty) {
      setState(() {
        _results = [];
        _hasSearched = false;
        _isSearching = false;
        _errorMessage = null;
        _lastQuery = '';
      });
      return;
    }

    if (trimmed != _lastQuery) {
      setState(() => _isSearching = true);
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (trimmed != _lastQuery) {
        _runSearch(trimmed);
      } else {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) return;
    final svc = context.read<MFilesService>();

    setState(() {
      _isSearching = true;
      _isWarming = false;
      _errorMessage = null;
      _lastQuery = query;
    });

    try {
      if (_hasActiveFilters) {
        await svc.advancedSearchVault(
          query: query,
          objectTypeIds: _selectedObjectTypeIds.toList(),
          classId: _selectedClassId,
        );
      } else {
        await svc.searchVault(query);
      }
      if (!mounted) return;

      final results = List<ViewObject>.from(svc.searchResults);

      final q = query.toLowerCase();
      results.sort((a, b) {
        final aTitle = a.title.toLowerCase();
        final bTitle = b.title.toLowerCase();
        final aScore = aTitle.startsWith(q) ? 0 : aTitle.contains(q) ? 1 : 2;
        final bScore = bTitle.startsWith(q) ? 0 : bTitle.contains(q) ? 1 : 2;
        return aScore.compareTo(bScore);
      });

      setState(() {
        _results = results;
        _hasSearched = true;
        _isSearching = false;
        _isWarming = true;
        _expandedInfoItemId = null;
        _expandedRelationshipsItemId = null;
      });

      await Future.wait([
        svc.warmExtensionsForObjects(results),
        svc.warmRelationshipsForObjects(results),
      ]);

      if (!mounted) return;
      setState(() => _isWarming = false);

    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSearching = false;
        _isWarming = false;
        _errorMessage = e.toString();
        _hasSearched = true;
      });
    }
  }

  Future<void> _openPreview(ViewObject obj) async {
    if (_previewLoading.contains(obj.id)) return;
    setState(() => _previewLoading.add(obj.id));
    try {
      final svc = context.read<MFilesService>();
      final files = await svc.fetchObjectFiles(
        objectId: obj.id,
        classId: obj.classId,
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
            displayObjectId: obj.id,
            classId: obj.classId,
            fileId: f.fileId,
            fileTitle: f.fileTitle,
            extension: f.extension,
            reportGuid: f.reportGuid,
            objectTypeId: obj.objectTypeId,
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
      if (mounted) setState(() => _previewLoading.remove(obj.id));
    }
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
    if (_selectedIds.isEmpty) return;

    final confirmed = await showBatchDeleteConfirmDialog(
      context,
      count: _selectedIds.length,
    );

    if (confirmed != true || !mounted) return;

    _setProcessing(true, "Deleting objects...");
    try {
    final service = context.read<MFilesService>();

    final allObjects = <ViewObject>[
      ...service.recentObjects,
      ...service.assignedObjects,
      ...service.reportObjects,
      ...service.searchResults,
    ];

    final selectedObjects =
        allObjects.where((o) => _selectedIds.contains(o.id)).toList();

        debugPrint('Selected IDs: $_selectedIds');
        debugPrint('Matched objects: ${selectedObjects.length}');

    int success = 0;

    for (final obj in selectedObjects) {
      debugPrint(
        'Deleting: ${obj.title} | id=${obj.id} | classId=${obj.classId}',
      );

      final deleted = await service.deleteObject(
        objectId: obj.id,
        classId: obj.classId,
      );

      debugPrint('Delete result: $deleted');
      debugPrint('Service error: ${service.error}');

      if (deleted) success++;
    }

    _results.removeWhere((o) => _selectedIds.contains(o.id));

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

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Scaffold(
          backgroundColor: AppColors.surfaceLight,
          appBar: _buildAppBar(),
          body: NetworkBanner(
            child: Column(
              children: [
                _buildStatusBar(),

                if (_selectionMode)
                  _buildSelectionSummary(),

                Expanded(
                  child: _buildBody(),
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
                child: ProcessingDialog(
                  operation: _processingText,
                ),
              ),
            ),
          ),
      ],
    );
  }

  PreferredSizeWidget _buildAppBar() {
  if (!_selectionMode) {
    return _buildSearchAppBar();
  }

  return _searchWhileSelecting
      ? _buildSearchAppBar()
      : _buildSelectionAppBar();
}

  PreferredSizeWidget _buildSearchAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      toolbarHeight: 64,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
          if (_selectionMode && _searchWhileSelecting) {
            setState(() {
              _searchWhileSelecting = false;
            });
            return;
          }

          context.read<MFilesService>().clearSearchResults();
          Navigator.pop(context);
        },
      ),
      title: TextField(
        controller: _controller,
        focusNode: _focusNode,
        autofocus: false,
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: Colors.white, fontSize: 16),
        cursorColor: Colors.white70,
        decoration: InputDecoration(
          hintText: 'Search repository…',
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 16),
          border: InputBorder.none,
          isDense: true,
          contentPadding: EdgeInsets.zero,
        ),
        onChanged: _onQueryChanged,
        onSubmitted: (v) {
          _debounce?.cancel();
          final trimmed = v.trim();
          if (trimmed.isNotEmpty && trimmed != _lastQuery) {
            _runSearch(trimmed);
          }
        },
      ),
      actions: [
        _buildFilterIcon(),
        if (_controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: () {
              _debounce?.cancel();
              _controller.clear();
              _onQueryChanged('');

              if (_selectionMode) {
                setState(() {
                  _searchWhileSelecting = false;
                });
              }
            },
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  // Filter icon with indicator for active filters
  Widget _buildFilterIcon() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        IconButton(
          icon: const Icon(Icons.tune_rounded, color: Colors.white),
          onPressed: _openFilterSheet,
        ),
        if (_hasActiveFilters)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.orangeAccent,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _openFilterSheet() async {
    final svc = context.read<MFilesService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      if (svc.objectTypes.isEmpty) await svc.fetchObjectTypes();
      await Future.wait(
        svc.objectTypes.map((ot) => svc.fetchObjectClasses(ot.id)),
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load filter options: $e')),
      );
      return;
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop();

    final allClasses = svc.getAllClasses();

    // Local working copies so closing without Apply doesn't change state
    Set<int> workingTypes = Set.from(_selectedObjectTypeIds);
    int? workingClassId = _selectedClassId;

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.8,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.primary,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Filter Search',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.grey),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Object Type',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...svc.objectTypes.map((ot) {
                        final checked = workingTypes.contains(ot.id);
                        return CheckboxListTile(
                          value: checked,
                          onChanged: (v) {
                            setSheet(() {
                              if (v == true) {
                                workingTypes.add(ot.id);
                              } else {
                                workingTypes.remove(ot.id);
                              }
                            });
                          },
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          activeColor: AppColors.primary,
                          title: Text(
                            ot.displayName,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }),
                      const SizedBox(height: 12),
                      Text(
                        'Class',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      DropdownButtonFormField<int?>(
                        value: workingClassId,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.surfaceLight,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: Colors.grey.shade200),
                          ),
                        ),
                        hint: const Text('Any class'),
                        items: [
                          const DropdownMenuItem<int?>(
                            value: null,
                            child: Text('Any class'),
                          ),
                          ...allClasses.map(
                            (c) => DropdownMenuItem<int?>(
                              value: c.id,
                              child: Text(c.displayName, overflow: TextOverflow.ellipsis),
                            ),
                          ),
                        ],
                        onChanged: (v) => setSheet(() => workingClassId = v),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        setSheet(() {
                          workingTypes = {};
                          workingClassId = null;
                        });
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade700,
                        side: BorderSide(color: Colors.grey.shade300),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Clear'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _selectedObjectTypeIds
                            ..clear()
                            ..addAll(workingTypes);
                          _selectedClassId = workingClassId;
                        });
                        Navigator.pop(ctx);
                        if (_lastQuery.isNotEmpty) {
                          _runSearch(_lastQuery);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Apply'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
        onPressed: _clearSelection,
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
            _showSelectedOnly = false;
            _searchWhileSelecting = true;
          });

          _focusNode.requestFocus();
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
                    converted == 1
                        ? 'Converted 1 object'
                        : 'Converted $converted objects',
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


  Widget _buildStatusBar() {
    final query = _controller.text.trim();

    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.search, size: 13, color: AppColors.primary),
                const SizedBox(width: 5),
                Text(
                  '"$query"',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          if (_isSearching)
            Row(
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      AppColors.primary.withOpacity(0.6),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Searching…',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                ),
              ],
            )
          else if (_isWarming)
            Row(
              children: [
                SizedBox(
                  width: 13,
                  height: 13,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(
                      Colors.orange.withOpacity(0.7),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Loading more results…',
                  style: TextStyle(fontSize: 12, color: Colors.orange.shade600),
                ),
              ],
            )
          else if (_hasSearched)
            Text(
              _errorMessage != null
                  ? 'Search failed'
                  : '${_results.length} result${_results.length == 1 ? '' : 's'}',
              style: TextStyle(
                fontSize: 12,
                color: _errorMessage != null
                    ? Colors.red.shade600
                    : Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
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
        color: _showSelectedOnly
        ? Colors.green.shade50
        : AppColors.primary.withOpacity(0.05),
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
              _showSelectedOnly
              ? 'Reviewing ${_selectedIds.length} selected items'
              : '${_selectedIds.length} items selected across searches',
              style: const TextStyle(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          TextButton(
            onPressed: () {
              setState(() {
              _showSelectedOnly = !_showSelectedOnly;
            });
            },
            child: Text(
              _showSelectedOnly ? 'Show All' : 'Review',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody() {
    final query = _controller.text.trim();

    if (query.isEmpty) {
      return _buildIdleState();
    }

    if (_isSearching && _results.isEmpty) {
      return _buildLoadingState(query);
    }

    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    if (_results.isNotEmpty) {
      return _buildResultsList();
    }

    if (_hasSearched && !_isSearching) {
      return _buildEmptyState(query);
    }

    return const SizedBox.shrink();
  }

  Widget _buildIdleState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.search_rounded,
                size: 48,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Search the repository',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Start typing to search across all objects,\ndocuments and folders.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.surfaceLight, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingState(String query) {
    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: 6,
            itemBuilder: (_, i) => _ShimmerRow(delay: i * 80),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String query) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 20),
            const Text(
              'No results found',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: Color(0xFF1A1A1A),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'No items matched "$query".\nTry a different search term.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: AppColors.surfaceLight, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 48, color: Colors.red.shade400),
            ),
            const SizedBox(height: 20),
            const Text(
              'Search failed',
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF1A1A1A)),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => _runSearch(_lastQuery),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Try again'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    final displayedResults = _showSelectedOnly
        ? _selectedObjects.values.toList()
        : _results;

    return Scrollbar(
      controller: _scrollController,
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(8),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        itemCount: displayedResults.length,
        itemBuilder: (context, index) =>
            _buildObjectRow(displayedResults[index]),
      ),
    );
  }

  Widget _buildObjectRow(ViewObject obj) {
    final svc = context.watch<MFilesService>();
    final type = obj.objectTypeName.trim();
    final idPart = obj.displayId.trim().isNotEmpty ? obj.displayId.trim() : '${obj.id}';
    final subtitle = type.isEmpty ? 'ID $idPart' : '$type | ID $idPart';

    final bool canExpand = obj.id != 0;
    final bool isDoc = svc.isDocumentViewObject(obj);
    final bool infoExpanded = _expandedInfoItemId == obj.id;
    final bool relationshipsExpanded = _expandedRelationshipsItemId == obj.id;
    final bool isDimmed = _expandedInfoItemId != null && !infoExpanded;
    final bool hasRelationships = svc.cachedHasRelationships(obj.id) == true;

    // Resolve extension for document rows
    final String? ext = isDoc ? svc.cachedExtensionForObject(obj.id) : null;

    if (canExpand && svc.cachedHasRelationships(obj.id) == null) {
      svc.ensureRelationshipsPresenceForObject(
        objectId: obj.id,
        objectTypeId: obj.objectTypeId,
        classId: obj.classId,
        notify: false,
      );
    }

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isDimmed ? 0.45 : 1.0,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: _isSelected(obj.id)
          ? AppColors.primary.withOpacity(0.08)
          : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border:
              infoExpanded
                  ? Border.all(color: AppColors.primary, width: 1.5)
                  : null,
          boxShadow: infoExpanded
              ? [
                  BoxShadow(
                    color: AppColors.primary.withOpacity(0.25),
                    blurRadius: 14,
                    spreadRadius: 1,
                    offset: const Offset(0, 2),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Column(
          children: [
            Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () async {
                if (_selectionMode) {
                  _toggleSelection(obj);
                  return;
                }

                if (isDimmed) {
                  setState(() => _expandedInfoItemId = null);
                  return;
                }

                await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ObjectDetailsScreen(obj: obj),
                  ),
                );
              },

              onLongPress: () {
                if (!_selectionMode) {
                  _toggleSelection(obj);
                }
              },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Relationships chevron
                      if (canExpand && hasRelationships) ...[
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_expandedRelationshipsItemId == obj.id) {
                                  _expandedRelationshipsItemId = null;
                                } else {
                                  _expandedRelationshipsItemId = obj.id;
                                  _expandedInfoItemId = null;
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(4),
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
                        ),
                        const SizedBox(width: 6),
                      ] else
                        const SizedBox(width: 4),

                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: (_selectionMode && _isSelected(obj.id))
                            ? Container(
                                key: const ValueKey('selected'),
                                width: 42,
                                height: 42,
                                decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              )
                            : Container(
                                key: const ValueKey('normal'),
                                child: isDoc
                                    ? FileTypeBadge(
                                        extension: ext ?? '',
                                        size: 28,
                                      )
                                    : const Icon(
                                        Icons.folder_rounded,
                                        color: AppColors.primary,
                                        size: 22,
                                      ),
                              ),
                      ),

                      const SizedBox(width: 12),

                      // Title + subtitle
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _HighlightedText(
                              text: obj.title,
                              query: _controller.text.trim(),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              subtitle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ],
                        ),
                      ),

                      // Eye icon (documents only)
                      if (isDoc) ...[
                        const SizedBox(width: 8),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _openPreview(obj),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.blueGrey.withOpacity(0.08),
                              shape: BoxShape.circle,
                            ),
                            child: _previewLoading.contains(obj.id)
                                ? SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation<Color>(
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

                      // Info icon (all expandable objects)
                      if (canExpand) ...[
                        const SizedBox(width: 8),
                        Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              setState(() {
                                if (_expandedInfoItemId == obj.id) {
                                  _expandedInfoItemId = null;
                                } else {
                                  _expandedInfoItemId = obj.id;
                                  _expandedRelationshipsItemId = null;
                                }
                              });
                            },
                            borderRadius: BorderRadius.circular(20),
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
                        ),
                      ] else
                        Icon(Icons.chevron_right_rounded,
                            size: 20, color: Colors.grey.shade400),
                    ],
                  ),
                ),
              ),
            ),

            if (infoExpanded && canExpand) ...[
              Divider(height: 1, color: Colors.grey.shade200),
              ObjectInfoDropdown(obj: obj),
            ],

            if (relationshipsExpanded && canExpand) ...[
              Divider(height: 1, color: Colors.grey.shade200),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: RelationshipsDropdown(
                  key: ValueKey('rel_${obj.id}'),
                  obj: obj,
                  initiallyExpanded: true,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// Highlights matching query text in result titles

class _HighlightedText extends StatelessWidget {
  final String text;
  final String query;

  const _HighlightedText({required this.text, required this.query});

  @override
  Widget build(BuildContext context) {
    if (query.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
      );
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: const TextStyle(
          color: AppColors.primary,
          fontWeight: FontWeight.w800,
          backgroundColor: Color(0xFFDCEAFF),
        ),
      ));
      start = index + query.length;
    }

    return Text.rich(
      TextSpan(
        style: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1A1A1A)),
        children: spans,
      ),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

// Shimmer placeholder row

class _ShimmerRow extends StatefulWidget {
  final int delay;
  const _ShimmerRow({required this.delay});

  @override
  State<_ShimmerRow> createState() => _ShimmerRowState();
}

class _ShimmerRowState extends State<_ShimmerRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    Future.delayed(Duration(milliseconds: widget.delay), () {
      if (mounted) _ctrl.repeat(reverse: true);
    });
    _anim = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (_, __) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(_anim.value),
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FractionallySizedBox(
                    widthFactor: 0.55 + (_anim.value * 0.1),
                    child: Container(
                      height: 13,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(_anim.value),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 7),
                  FractionallySizedBox(
                    widthFactor: 0.35,
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.grey.withOpacity(_anim.value * 0.6),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: Colors.grey.withOpacity(_anim.value * 0.4),
                shape: BoxShape.circle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}