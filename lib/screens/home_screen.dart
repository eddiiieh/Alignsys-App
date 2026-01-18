import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
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
          backgroundColor: const Color.fromARGB(255, 251, 251, 251),
          elevation: 0,
          toolbarHeight: 56,
          titleSpacing: 12,
          title: ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: Image.asset(
              'assets/alignsyslogo.png',
              height: 32,
              fit: BoxFit.cover,
            ),
          ),
          actions: [
            TextButton.icon(
              onPressed: () => _showCreateMenu(context),
              icon: const Icon(Icons.add,
                  size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
              label: const Text(
                'Create',
                style: TextStyle(
                    fontSize: 14,
                    color: Color.fromRGBO(25, 76, 129, 1)),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.person,
                  color: Color.fromRGBO(25, 76, 129, 1)),
              onPressed: () => _showProfileMenu(context),
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
    padding: const EdgeInsets.symmetric(horizontal: 16),
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
      onChanged: (value) {
        _searchQuery = value.trim();
      },
      onSubmitted: (_) => _executeSearch(),
    ),
  );
}


  Widget _buildTabBar() {
    return Align(
      alignment: Alignment.centerLeft,
      child: TabBar(
        controller: _tabController,
        isScrollable: true,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        labelPadding: const EdgeInsets.only(right: 24),
        labelColor: const Color.fromRGBO(25, 76, 129, 1),
        unselectedLabelColor: Colors.grey,
        indicatorColor: const Color.fromRGBO(25, 76, 129, 1),
        indicatorWeight: 3,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
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
            padding: const EdgeInsets.all(16),
            children: [
              if (service.commonViews.isNotEmpty) ...[
                _buildSectionHeader('Common Views', Icons.star),
                const SizedBox(height: 12),
                ...service.commonViews.map(_buildViewCard),
                const SizedBox(height: 24),
              ],
              _buildSectionHeader('Other Views', Icons.folder_outlined),
              const SizedBox(height: 12),
              if (service.otherViews.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(
                      child: Text('No views available',
                          style: TextStyle(color: Colors.grey))),
                )
              else
                ...service.otherViews.map(_buildViewCard),
            ],
          ),
        );
      },
    );
  }

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
    return const Center(child: Text('Deleted objects - no results found'));
  }

  Widget _buildReportsTab() {
    return const Center(child: Text('Reports - no results found'));
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
          return Center(child: Text(emptyText));
        }

        return RefreshIndicator(
          onRefresh: () => onRefresh(service),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: objects.length,
            itemBuilder: (context, index) =>
                _buildObjectCard(objects[index]),
          ),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: const Color.fromRGBO(25, 76, 129, 1), size: 20),
        const SizedBox(width: 8),
        Text(
          title,
          style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color.fromRGBO(25, 76, 129, 1)),
        ),
      ],
    );
  }

  Widget _buildViewCard(ViewItem view) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(view.name),
        subtitle: Text('${view.count} items'),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  Widget _buildObjectCard(ViewObject obj) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        title: Text(obj.title),
        subtitle: Text(obj.objectType),
        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
      ),
    );
  }

  void _showCreateMenu(BuildContext context) {}
  void _showProfileMenu(BuildContext context) {}

  Future<void> _executeSearch() async {
  if (_searchQuery.isEmpty) return;

  final service = context.read<MFilesService>();
  await service.searchVault(_searchQuery);

  if (_tabController.index != 1) {
    _tabController.animateTo(1);
  }
}

}
