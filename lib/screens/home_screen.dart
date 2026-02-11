import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/screens/view_details_screen.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
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

  static const double _sectionSpacing = 12;

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

    // ✅ Ensure M-Files user id is available for vault-scoped endpoints
    await service.fetchMFilesUserId();

    await service.fetchObjectTypes();
    await service.fetchAllViews();
    await service.fetchRecentObjects();
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
          title: Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              // ignore: deprecated_member_use
              color: Colors.white.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.asset(
                'assets/alignsysop.png',
                height: 34,
                fit: BoxFit.cover,
              ),
            ),
          ),
          actions: [
            Builder(
              builder: (BuildContext buttonContext) {
                return TextButton.icon(
                  onPressed: () => _showCreateMenu(buttonContext),
                  icon: const Icon(Icons.add, size: 20, color: Color.fromARGB(255, 251, 251, 251)),
                  label: const Text(
                    'Create',
                    style: TextStyle(fontSize: 14, color: Color.fromARGB(255, 251, 251, 251)),
                  ),
                );
              },
            ),
            Builder(
              builder: (BuildContext buttonContext) {
                return IconButton(
                  icon: const Icon(Icons.person, color: Color.fromARGB(255, 251, 251, 251)),
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
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TextField(
        controller: _searchController,
        focusNode: _searchFocus,
        textInputAction: TextInputAction.search,
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
            borderSide: const BorderSide(
              color: Color.fromRGBO(25, 76, 129, 1),
              width: 2,
            ),
          ),
          filled: true,
          fillColor: Colors.grey.shade50,
          contentPadding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),

          // ✅ Keep everything in suffixIcon slot (stable height)
          suffixIconConstraints: BoxConstraints(
            minHeight: 40,
            minWidth: hasText ? 88 : 48, // enough for (X + search) or (search)
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasText)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  tooltip: 'Clear',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                    _searchFocus.requestFocus();
                  },
                ),
              IconButton(
                icon: const Icon(Icons.search, color: Color.fromRGBO(25, 76, 129, 1)),
                tooltip: 'Search',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                onPressed: _executeSearch,
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
        onChanged: (value) => setState(() => _searchQuery = value.trim()),
        onSubmitted: (_) => _executeSearch(),
      ),
    );
  }

  Widget _buildTabBar() {
    return SizedBox(
      height: 40,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
        padding: const EdgeInsetsDirectional.only(start: 8),
        labelPadding: const EdgeInsetsDirectional.fromSTEB(0, 0, 24, 0),
        indicatorPadding: EdgeInsets.zero,
        labelColor: const Color.fromRGBO(25, 76, 129, 1),
        unselectedLabelColor: Colors.grey,
        indicatorColor: const Color.fromRGBO(25, 76, 129, 1),
        indicatorWeight: 3,
        labelStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15,
          height: 1.0,
        ),
        tabs: const [
          Tab(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home, size: 18),
                SizedBox(width: 6),
                Text('Home'),
              ],
            ),
          ),
          Tab(text: 'Recent'),
          Tab(text: 'Assigned'),
          Tab(text: 'Deleted'),
          Tab(text: 'Reports'),
        ],
        onTap: _onTabChanged,
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
          return Center(child: Text(service.error!));
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
              children: [
                _buildSection(
                  title: 'Common Views',
                  count: commonSorted.length,
                  expanded: _commonExpanded,
                  onToggle: () => setState(() => _commonExpanded = !_commonExpanded),
                  items: commonSorted,
                  emptyText: 'No common views',
                  leadingIcon: Icons.star,
                ),
                const SizedBox(height: 10),
                _buildSection(
                  title: 'Other Views',
                  count: otherSorted.length,
                  expanded: _otherExpanded,
                  onToggle: () => setState(() => _otherExpanded = !_otherExpanded),
                  items: otherSorted,
                  emptyText: 'No views available',
                  leadingIcon: Icons.folder_outlined,
                ),
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
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          child: expanded
              ? Column(
                  children: [
                    const SizedBox(height: 6),
                    if (items.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: Text(emptyText, style: TextStyle(color: Colors.grey.shade600)),
                      )
                    else
                      ..._buildFlatViewRows(items),
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 18, color: const Color.fromRGBO(25, 76, 129, 1)),
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
            Text('($count)', style: TextStyle(fontSize: 12, color: Colors.grey.shade700)),
            const SizedBox(width: 6),
            Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey.shade700),
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
        rows.add(Divider(height: 1, color: Colors.grey.shade200));
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.grid_view_rounded, size: 18, color: Color.fromRGBO(25, 76, 129, 1)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                view.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            if (view.count > 0) ...[
              Text('${view.count}', style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
              const SizedBox(width: 8),
            ],
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
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
      emptyIcon: Icons.history,
      emptyText: _searchQuery.isNotEmpty ? 'No results' : 'No recent objects',
      onRefresh: (s) => _searchQuery.isNotEmpty ? s.searchVault(_searchQuery) : s.fetchRecentObjects(),
    );
  }

  Widget _buildAssignedTab() {
    return _buildObjectList(
      selector: (s) => s.assignedObjects,
      emptyIcon: Icons.assignment,
      emptyText: 'No assigned objects',
      onRefresh: (s) => s.fetchAssignedObjects(),
    );
  }

  // NOTE: You currently don't have deleted/report objects in your service.
  // Keeping these as-is. If you add lists + fetch methods, wire them into _buildObjectList().
  Widget _buildDeletedTab() {
    return _buildObjectList(
      selector: (s) => s.deletedObjects, // list in your service
      emptyIcon: Icons.delete_outline,
      emptyText: 'No deleted objects',
      onRefresh: (s) => s.fetchDeletedObjects(),
    );
  }

  Widget _buildReportsTab() {
    return _buildObjectList(
      selector: (s) => s.reportObjects,
      emptyIcon: Icons.analytics_outlined,
      emptyText: 'No reports found',
      onRefresh: (s) => s.fetchReportObjects(),
    );
  }

  Widget _buildObjectList({
    required List<ViewObject> Function(MFilesService) selector,
    required IconData emptyIcon,
    required String emptyText,
    required Future<void> Function(MFilesService) onRefresh,
  }) {
    return Consumer<MFilesService>(
      builder: (context, service, _) {
        final objects = selector(service);

        service.warmExtensionsForObjects(objects);

        if (service.isLoading && objects.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }

        if (objects.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(emptyIcon, size: 64, color: Colors.grey.shade400),
                const SizedBox(height: 12),
                Text(
                  emptyText,
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
                ),
              ],
            ),
          );
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

  // UPDATED: show Name + Date Modified (remove type line)
  // UPDATED: show Name + (ObjectType | Last Modified) when type exists
  Widget _buildCompactObjectRow(ViewObject obj) {
    final type = obj.objectTypeName.trim();
    final modified = _formatModified(obj.lastModifiedUtc);
    final subtitle = type.isEmpty ? 'Modified: $modified' : '$type | $modified';

    final canExpand = obj.id != 0 && obj.objectTypeId != 0 && obj.classId != 0;

    // ✅ icon mapping: use cached extension if available; fallback to generic doc icon
    final svc = context.watch<MFilesService>();
    final mappedIcon = _iconForObj(svc, obj);

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          onExpansionChanged: (expanded) {
            if (!canExpand) return; // no-op
          },
          trailing: canExpand
              ? const Icon(Icons.expand_more, size: 18)
              : const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
          title: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final deleted = await Navigator.push<bool>(
                context,
                MaterialPageRoute(builder: (_) => ObjectDetailsScreen(obj: obj)),
              );

              if (deleted == true) {
                await context.read<MFilesService>().fetchRecentObjects();
              }
            },
            child: Row(
              children: [
                Icon(mappedIcon, size: 18, color: const Color.fromRGBO(25, 76, 129, 1)),
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
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          children: canExpand ? [RelationshipsDropdown(obj: obj)] : const [],
        ),
      ),
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

  void _showCreateMenu(BuildContext context) async {
    final service = context.read<MFilesService>();
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    final RelativeRect position = RelativeRect.fromLTRB(
      buttonPosition.dx + button.size.width - 200,
      buttonPosition.dy + button.size.height,
      0,
      0,
    );

    if (service.objectTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No object types available. Please wait for data to load.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final maxMenuHeight = MediaQuery.of(context).size.height * 0.6;

    showMenu<dynamic>(
      context: context,
      position: position,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      constraints: BoxConstraints(
        minWidth: 230,
        maxWidth: 230,
        maxHeight: maxMenuHeight,
      ),
      items: service.objectTypes.map((objectType) {
        return PopupMenuItem<dynamic>(
          value: objectType,
          child: Row(
            children: [
              Icon(
                objectType.isDocument ? Icons.description : Icons.folder,
                size: 20,
                color: const Color.fromRGBO(25, 76, 129, 1),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(objectType.displayName, style: const TextStyle(fontSize: 14)),
              ),
              const Icon(Icons.chevron_right, size: 18, color: Colors.grey),
            ],
          ),
        );
      }).toList(),
    ).then((selectedObjectType) {
      if (selectedObjectType != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => DynamicFormScreen(objectType: selectedObjectType)),
        );
      }
    });
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
            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
          ),
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // drag handle
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 14),

                // header
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        // ignore: deprecated_member_use
                        color: const Color(0xFF0A1541).withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person, color: Color(0xFF0A1541)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            service.username ?? 'Unknown',
                            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Account',
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 14),

                // vault dropdown (no popup dialog)
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Current Vault',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey.shade700),
                  ),
                ),
                const SizedBox(height: 8),

                FutureBuilder<List<Vault>>(
                  future: service.getUserVaults(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        alignment: Alignment.centerLeft,
                        child: const LinearProgressIndicator(minHeight: 2),
                      );
                    }
                    if (snapshot.hasError) {
                      return Text('Error loading vaults: ${snapshot.error}');
                    }

                    final vaults = snapshot.data ?? [];
                    if (vaults.isEmpty) return const Text('No vaults available');

                    final selectedGuid = service.selectedVault?.guid;

                    return DropdownButtonFormField<String>(
                      value: selectedGuid,
                      isExpanded: true,
                      decoration: InputDecoration(
                        filled: true,
                        fillColor: Colors.grey.shade50,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: Colors.grey.shade300),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      items: vaults.map((v) {
                        return DropdownMenuItem<String>(
                          value: v.guid,
                          child: Text(v.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        );
                      }).toList(),
                      onChanged: (guid) async {
                        if (guid == null) return;
                        if (guid == service.selectedVault?.guid) return;

                        final newVault = vaults.firstWhere((v) => v.guid == guid);

                        // switch vault in-place (no popup)
                        service.selectedVault = newVault;
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
                    );
                  },
                ),

                const SizedBox(height: 14),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 8),

                // actions
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.logout, color: Colors.red),
                  title: const Text('Log Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                  onTap: () {
                    Navigator.pop(context);
                    _handleLogout(context);
                  },
                ),

                const SizedBox(height: 6),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Log Out'),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
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
