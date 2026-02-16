import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/screens/view_details_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/widgets/object_info_bottom_sheet.dart';
import 'package:mfiles_app/widgets/object_info_dropdown.dart';
import 'package:provider/provider.dart';
import '../models/vault.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import '../widgets/relationships_dropdown.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> tabs = ['Home', 'Recent', 'Assigned', 'Deleted', 'Reports'];
  String _searchQuery = '';

  static const double _sectionSpacing = 10;

  bool _commonExpanded = true;
  bool _otherExpanded = true;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();

  // Scroll controllers for each tab (home + objects)
  final ScrollController _homeScroll = ScrollController();
  final ScrollController _objectsScroll = ScrollController();

  // NEW: central icon resolver method for content items
  IconData _iconForObj(MFilesService svc, ViewObject obj) {
    return svc.iconForViewObject(obj);
  }

  // Track which item is currently expanded for info
  int? _expandedInfoItemId;
  // Track which item is currently expanded for relationships
  int? _expandedRelationshipsItemId;

  List<ViewItem> _sortedViews(List<ViewItem> items) {
    final copy = List<ViewItem>.from(items);
    copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return copy;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  Future<void> _loadInitialData() async {
    final service = context.read<MFilesService>();

    try {
      // ✅ Ensure M-Files user id is available
      if (service.mfilesUserId == null) {
        await service.fetchMFilesUserId();
      }
      
      // ✅ Check again after fetch attempt
      if (service.mfilesUserId == null) {
        // Navigate back to login if still null
        if (mounted) {
          Navigator.pushReplacementNamed(context, '/login');
        }
        return;
      }

      await service.fetchObjectTypes();
      await service.fetchAllViews();
      await service.fetchRecentObjects();
    } catch (e) {
      print('Error loading initial data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error loading data: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onTabChanged(int index) {
    final service = context.read<MFilesService>();
    final tab = tabs[index];
    service.setActiveTab(tab);

    switch (tab) {
      case 'Recent':
        service.fetchRecentObjects();
        break;
      case 'Assigned':
        service.fetchAssignedObjects();
        break;
      case 'Deleted':
        service.fetchDeletedObjects();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _homeScroll.dispose();
    _objectsScroll.dispose();
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  // NEW: Date Modified formatter
  String _formatModified(DateTime? dt) {
    if (dt == null) return '—';
    final local = dt.toLocal();
    return DateFormat('dd MMM yyyy, HH:mm').format(local);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: const Color(0xFF0A1541),
          elevation: 0,
          toolbarHeight: 64,
          titleSpacing: 12,
          title: Consumer<MFilesService>(
            builder: (context, service, _) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset(
                        'assets/alignsysop.png',
                        height: 28,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          actions: [
            Builder(
              builder: (BuildContext buttonContext) {
                return TextButton.icon(
                  onPressed: () => _showCreateBottomSheet(buttonContext),
                  icon: const Icon(Icons.add, size: 20, color: Colors.white),
                  label: const Text(
                    'Create',
                    style: TextStyle(fontSize: 14, color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
            const SizedBox(width: 8),
            Builder(
              builder: (BuildContext buttonContext) {
                return IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    child: const Icon(Icons.person, size: 20, color: Colors.white),
                  ),
                  onPressed: () => _showProfileMenu(buttonContext),
                );
              },
            ),
            const SizedBox(width: 8),
          ],
        ),
        body: Column(
          children: [
            _buildSearchBar(),
            const SizedBox(height: _sectionSpacing),
            _buildTabBar(),
            const SizedBox(height: _sectionSpacing),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildHomeTab(),
                  _buildRecentTab(),
                  _buildAssignedTab(),
                  _buildDeletedTab(),
                  _buildReportsTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    final hasText = _searchController.text.trim().isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: 'Search...',
            hintStyle: TextStyle(color: Colors.grey.shade400),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
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
            contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            prefixIcon: Icon(
              Icons.search,
              color: Colors.grey.shade400,
            ),
            suffixIconConstraints: BoxConstraints(
              minHeight: 40,
              minWidth: hasText ? 48 : 0,
            ),
            suffixIcon: hasText
                ? IconButton(
                    icon: Icon(Icons.close, color: Colors.grey.shade400),
                    tooltip: 'Clear',
                    onPressed: () {
                      _searchController.clear();
                      setState(() => _searchQuery = '');
                      _searchFocus.unfocus();
                    },
                  )
                : null,
          ),
          onChanged: (value) => setState(() => _searchQuery = value.trim()),
          onSubmitted: (_) => _executeSearch(),
        ),
      ),
    );
  }

  Widget _buildTabBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.all(4),
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
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: EdgeInsets.zero,
        labelPadding: const EdgeInsets.symmetric(horizontal: 4),
        indicatorPadding: const EdgeInsets.all(4),
        dividerColor: Colors.transparent,
        indicator: BoxDecoration(
          color: const Color(0xFF072F5F),
          borderRadius: BorderRadius.circular(8),
        ),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 13,
        ),
        unselectedLabelStyle: const TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 13,
        ),
        tabs: [
          _buildTab(Icons.home_rounded, 'Home'),
          _buildTab(Icons.history_rounded, 'Recent'),
          _buildTab(Icons.assignment_rounded, 'Assigned'),
          _buildTab(Icons.delete_outline_rounded, 'Deleted'),
          _buildTab(Icons.analytics_outlined, 'Reports'),
        ],
        onTap: _onTabChanged,
      ),
    );
  }

  Widget _buildTab(IconData icon, String label) {
    return Tab(
      height: 36,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16),
            const SizedBox(width: 6),
            Text(label),
          ],
        ),
      ),
    );
  }

  // -----------------------------
  // HOME TAB
  // -----------------------------
  Widget _buildHomeTab() {
    return Consumer<MFilesService>(
      builder: (context, service, _) {
        if (service.isLoading && service.allViews.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (service.error != null && service.allViews.isEmpty) {
          return _buildErrorState(service.error!);
        }

        final commonSorted = _sortedViews(service.commonViews);
        final otherSorted = _sortedViews(service.otherViews);

        return RefreshIndicator(
          onRefresh: service.fetchAllViews,
          child: Scrollbar(
            controller: _homeScroll,
            thumbVisibility: false,
            interactive: true,
            thickness: 6,
            radius: const Radius.circular(8),
            child: ListView(
              controller: _homeScroll,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
              children: [
                _buildSection(
                  title: 'Common Views',
                  count: commonSorted.length,
                  expanded: _commonExpanded,
                  onToggle: () => setState(() => _commonExpanded = !_commonExpanded),
                  items: commonSorted,
                  emptyText: 'No common views',
                  leadingIcon: Icons.star_rounded,
                ),
                const SizedBox(height: 10),
                _buildSection(
                  title: 'Other Views',
                  count: otherSorted.length,
                  expanded: _otherExpanded,
                  onToggle: () => setState(() => _otherExpanded = !_otherExpanded),
                  items: otherSorted,
                  emptyText: 'No views available',
                  leadingIcon: Icons.folder_rounded,
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSection({
    required String title,
    required int count,
    required bool expanded,
    required VoidCallback onToggle,
    required List<ViewItem> items,
    required String emptyText,
    required IconData leadingIcon,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeaderRow(
          title: title,
          count: count,
          expanded: expanded,
          onTap: onToggle,
          icon: leadingIcon,
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: expanded
              ? Column(
                  children: [
                    const SizedBox(height: 8),
                    if (items.isEmpty)
                      _buildEmptySection(emptyText)
                    else
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
                          children: _buildFlatViewRows(items),
                        ),
                      ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildSectionHeaderRow({
    required String title,
    required int count,
    required bool expanded,
    required VoidCallback onTap,
    required IconData icon,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFF072F5F).withOpacity(0.08),
              const Color(0xFF072F5F).withOpacity(0.03),
            ],
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color.fromRGBO(25, 76, 129, 1)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: Color.fromRGBO(25, 76, 129, 1),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF072F5F).withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '$count',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF072F5F),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              expanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
              color: const Color(0xFF072F5F),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptySection(String text) {
    return Container(
      padding: const EdgeInsets.all(24),
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
      child: Center(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_open_rounded, size: 32, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 12),
            Text(
              text,
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFlatViewRows(List<ViewItem> views) {
    final rows = <Widget>[];
    for (int i = 0; i < views.length; i++) {
      final view = views[i];
      rows.add(_buildFlatViewRow(view));
      if (i != views.length - 1) {
        rows.add(Divider(height: 1, thickness: 1, color: Colors.grey.shade100));
      }
    }
    return rows;
  }

  Widget _buildFlatViewRow(ViewItem view) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => ViewDetailsScreen(view: view)),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFF072F5F).withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.grid_view_rounded,
                size: 18,
                color: Color.fromRGBO(25, 76, 129, 1),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                view.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1A1A1A),
                ),
              ),
            ),
            if (view.count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${view.count}',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                ),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }

  // -----------------------------
  // OTHER TABS: show Name + Date Modified
  // -----------------------------
  Widget _buildRecentTab() {
    return _buildObjectList(
      selector: (s) => _searchQuery.isNotEmpty ? s.searchResults : s.recentObjects,
      emptyIcon: Icons.history_rounded,
      emptyText: _searchQuery.isNotEmpty ? 'No results found' : 'No recent documents',
      emptySubtext: _searchQuery.isNotEmpty ? 'Try a different search term' : 'Documents you open will appear here',
      onRefresh: (s) => _searchQuery.isNotEmpty ? s.searchVault(_searchQuery) : s.fetchRecentObjects(),
    );
  }

  Widget _buildAssignedTab() {
    return _buildObjectList(
      selector: (s) => s.assignedObjects,
      emptyIcon: Icons.assignment_rounded,
      emptyText: 'No assigned documents',
      emptySubtext: 'Documents assigned to you will appear here',
      onRefresh: (s) => s.fetchAssignedObjects(),
    );
  }

  Widget _buildDeletedTab() {
    return _buildObjectList(
      selector: (s) => s.deletedObjects,
      emptyIcon: Icons.delete_outline_rounded,
      emptyText: 'No deleted items',
      emptySubtext: 'Deleted documents will appear here',
      onRefresh: (s) => s.fetchDeletedObjects(),
    );
  }

  Widget _buildReportsTab() {
    return _buildObjectList(
      selector: (s) => s.reportObjects,
      emptyIcon: Icons.analytics_outlined,
      emptyText: 'No reports found',
      emptySubtext: 'Reports will appear here when available',
      onRefresh: (s) => s.fetchReportObjects(),
    );
  }

  Widget _buildObjectList({
    required List<ViewObject> Function(MFilesService) selector,
    required IconData emptyIcon,
    required String emptyText,
    required String emptySubtext,
    required Future<void> Function(MFilesService) onRefresh,
  }) {
    return Consumer<MFilesService>(
      builder: (context, service, _) {
        final objects = selector(service);

        if (service.isLoading && objects.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (objects.isEmpty) {
          return _buildEmptyState(emptyIcon, emptyText, emptySubtext);
        }

        return RefreshIndicator(
          onRefresh: () => onRefresh(service),
          child: Scrollbar(
            controller: _objectsScroll,
            thumbVisibility: false,
            interactive: true,
            thickness: 6,
            radius: const Radius.circular(8),
            child: ListView.builder(
              controller: _objectsScroll,
              padding: const EdgeInsets.all(16),
              itemCount: objects.length,
              itemBuilder: (context, index) => _buildCompactObjectRow(objects[index]),
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String text, String subtext) {
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
              child: Icon(icon, size: 48, color: Colors.grey.shade400),
            ),
            const SizedBox(height: 20),
            Text(
              text,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              subtext,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState(String error) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
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
              'Oops! Something went wrong',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1A1A1A),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactObjectRow(ViewObject obj) {
    final type = obj.objectTypeName.trim();
    final modified = _formatModified(obj.lastModifiedUtc);
    final subtitle = type.isEmpty ? 'Modified: $modified' : '$type | $modified';

    final canExpand = obj.id != 0 && obj.objectTypeId != 0 && obj.classId != 0;

    final svc = context.watch<MFilesService>();
    final mappedIcon = _iconForObj(svc, obj);

    final bool infoExpanded = _expandedInfoItemId == obj.id;
    final bool relationshipsExpanded = _expandedRelationshipsItemId == obj.id;

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
            onTap: () async {
              final deleted = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => ObjectDetailsScreen(obj: obj)),
              );

              if (deleted == true) {
                await context.read<MFilesService>().fetchRecentObjects();
              }
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  // Relationships chevron (left side)
                  if (canExpand) ...[
                    InkWell(
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
                    child: Icon(mappedIcon, size: 18, color: const Color.fromRGBO(25, 76, 129, 1)),
                  ),
                  const SizedBox(width: 12),

                  // Title & subtitle
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          obj.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF1A1A1A),
                          ),
                        ),
                        const SizedBox(height: 4),
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
                    ),
                  ),

                  // Info icon (right side) - only for valid objects
                  if (canExpand) ...[
                    const SizedBox(width: 8),
                    InkWell(
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
                    Icon(Icons.chevron_right_rounded, size: 20, color: Colors.grey.shade400),
                ],
              ),
            ),
          ),

          // Info dropdown
          if (infoExpanded && canExpand) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            ObjectInfoDropdown(obj: obj),
          ],

          // Relationships dropdown
          if (relationshipsExpanded && canExpand) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: RelationshipsDropdown(obj: obj),
            ),
          ],
        ],
      ),
    );
  }

  void _showObjectInfo(ViewObject obj) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => ObjectInfoBottomSheet(obj: obj),
    );
  }

  Future<void> _executeSearch() async {
    if (_searchQuery.isEmpty) return;

    final service = context.read<MFilesService>();
    await service.searchVault(_searchQuery);

    if (_tabController.index != 1) {
      _tabController.animateTo(1);
    }
  }

  // ✅ NEW: Create menu as bottom sheet instead of popup
  void _showCreateBottomSheet(BuildContext context) {
    final service = context.read<MFilesService>();

    if (service.objectTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No object types available. Please wait for data to load.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // Header
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: const Color(0xFF072F5F).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.add_circle_outline_rounded,
                      color: Color(0xFF072F5F),
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Create New',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Object types list
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: service.objectTypes.length,
                  separatorBuilder: (_, __) => Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, index) {
                    final objectType = service.objectTypes[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF072F5F).withOpacity(0.08),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          objectType.isDocument ? Icons.description_rounded : Icons.folder_rounded,
                          size: 20,
                          color: const Color.fromRGBO(25, 76, 129, 1),
                        ),
                      ),
                      title: Text(
                        objectType.displayName,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.grey.shade400,
                      ),
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DynamicFormScreen(objectType: objectType),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showProfileMenu(BuildContext context) {
    final service = context.read<MFilesService>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Drag handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 20),

                // Header
                Row(
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0A1541).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.person_rounded,
                        color: Color(0xFF0A1541),
                        size: 28,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.username ?? 'Unknown',
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Account Settings',
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 20),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 20),

                // Vault selector
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Current Vault',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                FutureBuilder<List<Vault>>(
                  future: service.getUserVaults(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        alignment: Alignment.centerLeft,
                        child: const LinearProgressIndicator(minHeight: 2),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text(
                        'Error loading vaults: ${snapshot.error}',
                        style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                      );
                    }

                    final vaults = snapshot.data ?? [];
                    if (vaults.isEmpty) {
                      return const Text('No vaults available');
                    }

                    final selectedGuid = service.selectedVault?.guid;

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: DropdownButtonFormField<String>(
                        value: selectedGuid,
                        isExpanded: true,
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: Colors.grey.shade50,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                        items: vaults.map((v) {
                          return DropdownMenuItem<String>(
                            value: v.guid,
                            child: Text(
                              v.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          );
                        }).toList(),
                        onChanged: (guid) async {
                          if (guid == null) return;
                          if (guid == service.selectedVault?.guid) return;

                          final newVault = vaults.firstWhere((v) => v.guid == guid);

                          await service.saveSelectedVault(newVault);
                          await service.fetchMFilesUserId();
                          await service.fetchObjectTypes();
                          await service.fetchAllViews();
                          await service.fetchRecentObjects();

                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Switched to ${newVault.name}'),
                                backgroundColor: const Color.fromRGBO(25, 76, 129, 1),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                      ),
                    );
                  },
                ),

                const SizedBox(height: 20),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 12),

                // Logout
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
                  ),
                  title: const Text(
                    'Log Out',
                    style: TextStyle(
                      color: Colors.red,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _handleLogout(context);
                  },
                ),

                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text(
          'Log Out',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancel',
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.pop(context);
              context.read<MFilesService>().logout();
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text('Log Out'),
          ),
        ],
      ),
    );
  }
}