import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
import 'package:mfiles_app/widgets/network_banner.dart';
import 'package:mfiles_app/widgets/object_info_dropdown.dart';
import 'package:mfiles_app/widgets/relationships_dropdown.dart';
import 'package:provider/provider.dart';

import '../models/view_object.dart';
import '../theme/app_colors.dart';

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
  bool _isWarming = false; // ← new state for background warming

  int? _expandedInfoItemId;
  int? _expandedRelationshipsItemId;

  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialQuery);
    _focusNode = FocusNode();

    // Kick off the initial query immediately
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

    // Show a subtle "typing…" indicator immediately
    if (trimmed != _lastQuery) {
      setState(() => _isSearching = true);
    }

    _debounce = Timer(const Duration(milliseconds: 500), () {
      if (trimmed != _lastQuery) {
        _runSearch(trimmed);
      } else {
        // Same query — stop spinner
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _runSearch(String query) async {
    if (query.isEmpty) return;
    final svc = context.read<MFilesService>();

    setState(() {
      _isSearching = true;
      _isWarming = false; // ← new state
      _errorMessage = null;
      _lastQuery = query;
    });

    try {
      await svc.searchVault(query);
      if (!mounted) return;

      final results = List<ViewObject>.from(svc.searchResults);

      // Sort by title relevance immediately
      final q = query.toLowerCase();
      results.sort((a, b) {
        final aTitle = a.title.toLowerCase();
        final bTitle = b.title.toLowerCase();
        final aScore = aTitle.startsWith(q) ? 0 : aTitle.contains(q) ? 1 : 2;
        final bScore = bTitle.startsWith(q) ? 0 : bTitle.contains(q) ? 1 : 2;
        return aScore.compareTo(bScore);
      });

      // Show results immediately
      setState(() {
        _results = results;
        _hasSearched = true;
        _isSearching = false;
        _isWarming = true; // ← still fetching in background
        _expandedInfoItemId = null;
        _expandedRelationshipsItemId = null;
      });

      // Warm in background
      await Future.wait([
        svc.warmExtensionsForObjects(results),
        svc.warmRelationshipsForObjects(results),
      ]);

      if (!mounted) return;
      setState(() => _isWarming = false); // ← done

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: _buildAppBar(),
      body: NetworkBanner(
        child: Column(
          children: [
            _buildStatusBar(),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: AppColors.primary,
      elevation: 0,
      toolbarHeight: 64,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Colors.white),
        onPressed: () {
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
        if (_controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            onPressed: () {
              _debounce?.cancel();
              _controller.clear();
              _onQueryChanged('');
            },
          ),
        const SizedBox(width: 4),
      ],
    );
  }

  /// Thin bar below the AppBar showing query context + result count / spinner
  Widget _buildStatusBar() {
    final query = _controller.text.trim();

    // Nothing typed yet
    if (query.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Query chip
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

          // Spinner or result count
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

  Widget _buildBody() {
    final query = _controller.text.trim();

    // Idle — nothing typed
    if (query.isEmpty) {
      return _buildIdleState();
    }

    // Searching (first load — no previous results)
    if (_isSearching && _results.isEmpty) {
      return _buildLoadingState(query);
    }

    // Error
    if (_errorMessage != null) {
      return _buildErrorState(_errorMessage!);
    }

    // Has results (possibly still refreshing in background)
    if (_results.isNotEmpty) {
      return _buildResultsList();
    }

    // No results
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
        // Animated shimmer rows
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
    return Scrollbar(
      controller: _scrollController,
      interactive: true,
      thickness: 6,
      radius: const Radius.circular(8),
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(10),
        itemCount: _results.length,
        itemBuilder: (context, index) => _buildObjectRow(_results[index]),
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

    // Warm cache passively
    if (canExpand && !isDoc && svc.cachedHasRelationships(obj.id) == null) {
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
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: infoExpanded
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
                  if (isDimmed) {
                    setState(() => _expandedInfoItemId = null);
                    return;
                  }
                  await Navigator.push<bool>(
                    context,
                    MaterialPageRoute(
                        builder: (_) => ObjectDetailsScreen(obj: obj)),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      // Relationships chevron
                      if (canExpand && !isDoc && hasRelationships) ...[
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

                      // Icon
                      isDoc
                          ? FileTypeBadge(
                              extension: svc.cachedExtensionForObject(obj.id) ?? '',
                              size: 28,
                            )
                          : const Icon(
                              Icons.folder_rounded,
                              color: AppColors.primary,
                              size: 22,
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

                      // Info button
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
                child: RelationshipsDropdown(obj: obj, initiallyExpanded: true),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Highlights matching query text in result titles ─────────────────────────

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

// ─── Shimmer placeholder row ──────────────────────────────────────────────────

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
            // Icon placeholder
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
                  // Title placeholder
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
                  // Subtitle placeholder
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
            // Info button placeholder
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