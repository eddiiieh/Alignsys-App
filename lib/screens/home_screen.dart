import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:mfiles_app/screens/view_details_screen.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../models/vault.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<String> tabs = ['Home', 'Recent', 'Assigned', 'Deleted', 'Reports'];
  String _searchQuery = '';

  static const double _sectionSpacing = 12;

  // Flat section toggles (tab-like headers)
  bool _commonExpanded = true;
  bool _otherExpanded = true;

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
      default:
        break;
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        appBar: AppBar(
          backgroundColor: const Color(0xFF072F5F),
          elevation: 0,
          toolbarHeight: 64,
          titleSpacing: 12,
          title: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.asset(
              'assets/alignsysop.png',
              height: 34,
              fit: BoxFit.cover,
            ),
          ),
          actions: [
            Builder(
              builder: (BuildContext buttonContext) {
                return TextButton.icon(
                  onPressed: () => _showCreateMenu(buttonContext),
                  icon: const Icon(Icons.add,
                      size: 20, color: Color.fromARGB(255, 251, 251, 251)),
                  label: const Text(
                    'Create',
                    style: TextStyle(
                        fontSize: 14,
                        color: Color.fromARGB(255, 251, 251, 251)),
                  ),
                );
              },
            ),
            Builder(
              builder: (BuildContext buttonContext) {
                return IconButton(
                  icon: const Icon(Icons.person,
                      color: Color.fromARGB(255, 251, 251, 251)),
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
            SizedBox(height: _sectionSpacing),
            _buildTabBar(),
            SizedBox(height: _sectionSpacing),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
      child: TextField(
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
          contentPadding:
              const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          suffixIcon: IconButton(
            icon: const Icon(
              Icons.search,
              color: Color.fromRGBO(25, 76, 129, 1),
            ),
            onPressed: _executeSearch,
          ),
        ),
        onChanged: (value) => _searchQuery = value.trim(),
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
  // HOME TAB: flat headers + lists
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

        return RefreshIndicator(
          onRefresh: service.fetchAllViews,
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            children: [
              _buildSection(
                title: 'Common Views',
                count: service.commonViews.length,
                expanded: _commonExpanded,
                onToggle: () =>
                    setState(() => _commonExpanded = !_commonExpanded),
                items: service.commonViews,
                emptyText: 'No common views',
                leadingIcon: Icons.star,
              ),
              const SizedBox(height: 10),
              _buildSection(
                title: 'Other Views',
                count: service.otherViews.length,
                expanded: _otherExpanded,
                onToggle: () => setState(() => _otherExpanded = !_otherExpanded),
                items: service.otherViews,
                emptyText: 'No views available',
                leadingIcon: Icons.folder_outlined,
              ),
            ],
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
                        child: Text(
                          emptyText,
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
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
            Icon(icon,
                size: 18, color: const Color.fromRGBO(25, 76, 129, 1)),
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
            Text(
              '($count)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(width: 6),
            Icon(
              expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
              color: Colors.grey.shade700,
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFlatViewRows(List<ViewItem> views) {
    final List<Widget> rows = [];
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
          MaterialPageRoute(
            builder: (_) => ViewDetailsScreen(view: view),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.grid_view_rounded,
                size: 18, color: Color.fromRGBO(25, 76, 129, 1)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                view.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              '${view.count}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  // -----------------------------
  // OTHER TABS: compact object rows
  // -----------------------------
  Widget _buildRecentTab() {
    return _buildObjectList(
      selector: (s) => s.recentObjects,
      emptyIcon: Icons.history,
      emptyText: 'No recent objects',
      onRefresh: (s) => s.fetchRecentObjects(),
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

  Widget _buildDeletedTab() {
    return const Center(child: Text('No deleted objects'));
  }

  Widget _buildReportsTab() {
    return const Center(child: Text('No reports found'));
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
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: objects.length,
            itemBuilder: (context, index) =>
                _buildCompactObjectRow(objects[index]),
          ),
        );
      },
    );
  }

  Widget _buildCompactObjectRow(ViewObject obj) {
    return InkWell(
      onTap: () {
        //ADD NAVIG PUSH TO OBJECT DETAILS SCREEN
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            const Icon(Icons.description_outlined,
                size: 18, color: Color.fromRGBO(25, 76, 129, 1)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    obj.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    obj.objectTypeName.isNotEmpty ? obj.objectTypeName : obj.classTypeName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        TextStyle(fontSize: 12, color: Colors.grey.shade600),
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
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
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
          content:
              Text('No object types available. Please wait for data to load.'),
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
                child: Text(objectType.displayName,
                    style: const TextStyle(fontSize: 14)),
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
          MaterialPageRoute(
            builder: (_) => DynamicFormScreen(objectType: selectedObjectType),
          ),
        );
      }
    });
  }

  void _showProfileMenu(BuildContext context) {
    final service = context.read<MFilesService>();
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay =
        Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);

    final RelativeRect position = RelativeRect.fromLTRB(
      buttonPosition.dx + button.size.width - 220,
      buttonPosition.dy + button.size.height,
      0,
      0,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      constraints: const BoxConstraints(minWidth: 220, maxWidth: 220),
      items: [
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.person,
                      size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
                  SizedBox(width: 8),
                  Text('Account',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                service.username ?? 'Unknown',
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500),
              ),
              const Divider(height: 16),
            ],
          ),
        ),
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: const [
                  Icon(Icons.storage,
                      size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
                  SizedBox(width: 8),
                  Text('Current Vault',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey)),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                service.selectedVault?.name ?? 'None',
                style: const TextStyle(
                    fontSize: 14,
                    color: Colors.black87,
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'switch_vault',
          child: const Row(
            children: [
              Icon(Icons.swap_horiz,
                  size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
              SizedBox(width: 12),
              Text('Switch Vault'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<String>(
          value: 'logout',
          child: const Row(
            children: [
              Icon(Icons.logout, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text('Log Out', style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    ).then((value) {
      if (value == 'switch_vault') {
        _showVaultSwitchDialog(context);
      } else if (value == 'logout') {
        _handleLogout(context);
      }
    });
  }

  void _showVaultSwitchDialog(BuildContext context) {
    final service = context.read<MFilesService>();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Switch Vault'),
        content: FutureBuilder<List<Vault>>(
          future: service.getUserVaults(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()));
            }

            if (snapshot.hasError) {
              return Text('Error loading vaults: ${snapshot.error}');
            }

            final vaults = snapshot.data ?? [];

            if (vaults.isEmpty) {
              return const Text('No vaults available');
            }

            return SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: vaults.length,
                itemBuilder: (context, index) {
                  final vault = vaults[index];
                  final isSelected = service.selectedVault?.guid == vault.guid;

                  return ListTile(
                    leading: Icon(
                      Icons.storage,
                      color: isSelected
                          ? const Color.fromRGBO(25, 76, 129, 1)
                          : Colors.grey,
                    ),
                    title: Text(
                      vault.name,
                      style: TextStyle(
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected
                            ? const Color.fromRGBO(25, 76, 129, 1)
                            : Colors.black87,
                      ),
                    ),
                    trailing: isSelected
                        ? const Icon(Icons.check_circle,
                            color: Color.fromRGBO(25, 76, 129, 1))
                        : null,
                    onTap: isSelected
                        ? null
                        : () async {
                            Navigator.pop(context);
                            service.selectedVault = vault;
                            await service.fetchMFilesUserId();
                            await service.fetchObjectTypes();
                            await service.fetchAllViews();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Switched to ${vault.name}'),
                                  backgroundColor:
                                      const Color.fromRGBO(25, 76, 129, 1),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            }
                          },
                  );
                },
              ),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
        ],
      ),
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
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
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
