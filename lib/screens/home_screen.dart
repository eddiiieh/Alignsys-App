// ignore_for_file: use_build_context_synchronously, duplicate_ignore, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:mfiles_app/models/object_class.dart';
import 'package:mfiles_app/models/vault_object_type.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/screens/template_form_screen.dart';
import 'package:mfiles_app/screens/view_details_screen.dart';
import 'package:mfiles_app/widgets/network_banner.dart';
import 'package:mfiles_app/services/mfiles_service.dart';
import 'package:mfiles_app/utils/delete_object_helper.dart';
import 'package:mfiles_app/widgets/object_info_dropdown.dart';
import 'package:provider/provider.dart';
import '../models/vault.dart';
import '../models/view_item.dart';
import '../models/view_object.dart';
import '../widgets/relationships_dropdown.dart';
import 'package:mfiles_app/widgets/file_type_badge.dart';
import 'package:mfiles_app/screens/search_results_screen.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_colors.dart';
import 'package:mfiles_app/screens/document_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Tabs: Home | Recent | Assigned | Trash | Reports
  // (Signing moved to FAB)
  final List<String> tabs = ['Home', 'Recent', 'Assigned', 'Trash', 'Reports'];

  bool _switchingVault = false;
  String _switchingVaultName = '';

  String _searchQuery = '';

  static const double _sectionSpacing = 10;

  bool _commonExpanded = true;
  bool _otherExpanded = true;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final ScrollController _homeScroll = ScrollController();

  int? _expandedInfoItemId;
  int? _expandedRelationshipsItemId;

  final Set<int> _previewLoading = {};

  IconData _iconForObj(MFilesService svc, ViewObject obj) =>
      svc.iconForViewObject(obj);

  bool _isDocumentObj(MFilesService svc, ViewObject obj) =>
      svc.isDocumentViewObject(obj);

  List<ViewItem> _sortedViews(List<ViewItem> items) {
    final copy = List<ViewItem>.from(items);
    copy.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return copy;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: tabs.length, vsync: this);

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      setState(() {});
      _onTabChanged(_tabController.index);
      if (tabs[_tabController.index] == 'Home') _resetSearch();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) => _loadInitialData());
  }

  Widget _buildDocumentBadge(MFilesService svc, ViewObject obj) {
    final isTrashed = svc.isObjectDeleted(obj.id);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        FileTypeBadge(
          extension: svc.cachedExtensionForObject(obj.id) ?? '',
          size: 28,
          opacity: isTrashed ? 0.55 : 1.0,
        ),
        if (isTrashed)
          Positioned(
            bottom: -3,
            right: -5,
            child: Container(
              width: 15,
              height: 15,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.red.shade700, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 2,
                    offset: const Offset(0, 1),
                  ),
                ],
              ),
              child: Center(
                child: Icon(Icons.remove, size: 9, color: Colors.red.shade700),
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _loadInitialData() async {
    final service = context.read<MFilesService>();
    try {
      if (service.mfilesUserId == null) await service.fetchMFilesUserId();
      if (service.mfilesUserId == null) {
        if (mounted) Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      await Future.wait([
        service.fetchObjectTypes(),
        service.fetchAllViews(),
        service.fetchRecentObjects(),
        service.fetchAssignedObjects(),
        service.fetchDeletedObjects(),
      ]);
      await service.fetchReportObjects();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ));
      }
    }
  }

  void _onTabChanged(int index) {
    final service = context.read<MFilesService>();
    final tab = tabs[index];
    service.setActiveTab(tab);

    switch (tab) {
      case 'Recent':
        service.fetchRecentObjects(background: true);
        break;
      case 'Assigned':
        service.fetchAssignedObjects(background: true);
        break;
      case 'Trash':
        service.fetchDeletedObjects(background: true);
        break;
      case 'Reports':
        service.fetchReportObjects();
        break;
      default:
        break;
    }
  }

  Future<void> _refreshActiveTab() async {
    final service = context.read<MFilesService>();
    final tab = tabs[_tabController.index];
    switch (tab) {
      case 'Recent':
        await service.fetchRecentObjects();
        break;
      case 'Assigned':
        await service.fetchAssignedObjects();
        break;
      case 'Trash':
        await service.fetchDeletedObjects();
        break;
      case 'Reports':
        await service.fetchReportObjects();
        break;
      default:
        break;
    }
  }

  @override
  void dispose() {
    _homeScroll.dispose();
    _tabController.dispose();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
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
      debugPrint(
          '🔍 fileId=${f.fileId} fileTitle=${f.fileTitle} ext=${f.extension}');

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

  IconData _iconForObjectTypeName(String name) {
    final n = name.toLowerCase().trim();
    if (n == 'cars' || n.contains('vehicle'))
      return Icons.directions_car_rounded;
    if (n == 'container files') return Icons.folder_zip_rounded;
    if (n == 'document collections') return Icons.library_books_rounded;
    if (n == 'news') return Icons.newspaper_rounded;
    if (n == 'students') return Icons.school_rounded;
    if (n == 'annotations') return Icons.rate_review_rounded;
    if (n == 'archive boxes') return Icons.archive_rounded;
    if (n == 'calendar events') return Icons.event_rounded;
    if (n == 'customers') return Icons.people_alt_rounded;
    if (n == 'departments') return Icons.account_tree_rounded;
    if (n == 'filing slots') return Icons.inbox_rounded;
    if (n == 'finances') return Icons.account_balance_rounded;
    if (n == 'insurers') return Icons.health_and_safety_rounded;
    if (n == 'job vacancies') return Icons.work_history_rounded;
    if (n == 'library books') return Icons.menu_book_rounded;
    if (n == 'librarys' || n == 'libraries') return Icons.local_library_rounded;
    if (n == 'prescription sales') return Icons.medication_rounded;
    if (n == 'processes') return Icons.account_tree_rounded;
    if (n == 'requisitions') return Icons.request_page_rounded;
    if (n == 'shares') return Icons.share_rounded;
    if (n == 'test') return Icons.science_rounded;
    if (n == 'loans') return Icons.local_atm_rounded;
    if (n == 'members') return Icons.person_2_rounded;
    if (n == 'valuers') return Icons.currency_exchange_rounded;
    if (n.contains('contact') || n.contains('person') || n.contains('client'))
      return Icons.person_rounded;
    if (n.contains('project')) return Icons.work_rounded;
    if (n.contains('invoice')) return Icons.receipt_long_rounded;
    if (n.contains('payment') || n.contains('transaction'))
      return Icons.payments_rounded;
    if (n.contains('contract') || n.contains('agreement'))
      return Icons.handshake_rounded;
    if (n.contains('report') || n.contains('analytics'))
      return Icons.analytics_rounded;
    if (n.contains('meeting') || n.contains('minute'))
      return Icons.groups_rounded;
    if (n.contains('task') || n.contains('assignment'))
      return Icons.task_alt_rounded;
    if (n.contains('email') || n.contains('message') || n.contains('mail'))
      return Icons.email_rounded;
    if (n.contains('asset') || n.contains('equipment'))
      return Icons.inventory_2_rounded;
    if (n.contains('employee') || n.contains('staff') || n.contains('user'))
      return Icons.badge_rounded;
    if (n.contains('supplier') || n.contains('vendor'))
      return Icons.local_shipping_rounded;
    if (n.contains('company') ||
        n.contains('organisation') ||
        n.contains('organization')) return Icons.business_rounded;
    if (n.contains('case') || n.contains('ticket') || n.contains('issue'))
      return Icons.support_agent_rounded;
    if (n.contains('product') || n.contains('item') || n.contains('sku'))
      return Icons.inventory_rounded;
    if (n.contains('property') ||
        n.contains('real estate') ||
        n.contains('land')) return Icons.home_work_rounded;
    return Icons.category_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Stack(
        children: [
          Scaffold(
            backgroundColor: AppColors.surfaceLight,
            // ── DSS e-Signing FAB ──────────────────────────────────────────
            // NEW
            floatingActionButton: AnimatedBuilder(
              animation: _tabController,
              builder: (_, __) {
                final onHomeTab = _tabController.index == 0;
                return AnimatedSlide(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeInOut,
                  offset: onHomeTab ? Offset.zero : const Offset(0, 2.5),
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 180),
                    opacity: onHomeTab ? 1.0 : 0.0,
                    child: Builder(
                      builder: (ctx) => FloatingActionButton.extended(
                        onPressed: onHomeTab ? () => _showCreateBottomSheet(ctx) : null,
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 4,
                        icon: const Icon(Icons.add_rounded, size: 22),
                        label: const Text(
                          'Create',
                          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
            appBar: AppBar(
              backgroundColor: AppColors.primary,
              elevation: 0,
              toolbarHeight: 64,
              titleSpacing: 12,
              title: GestureDetector(
                onTap: () async {
                  final uri = Uri.parse('https://alignsys.tech');
                  final launched = await launchUrl(uri,
                      mode: LaunchMode.externalApplication);
                  if (!launched && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Could not open Alignsys website')),
                    );
                  }
                },
                child: Container(
                  padding: const EdgeInsets.all(4),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset('assets/alignsysnew.png',
                        height: 36, fit: BoxFit.cover),
                  ),
                ),
              ),
              actions: [
                Consumer<MFilesService>(
                  builder: (ctx, svc, _) {
                    final vaultName = svc.selectedVault?.name ?? '';
                    final display = vaultName.length > 18
                        ? '${vaultName.substring(0, 18)}…'
                        : vaultName;
                    return GestureDetector(
                      onTap: () => _showVaultSwitcher(ctx),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 12),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white.withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.storage_rounded, size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            Text(
                              display.isEmpty ? 'Vault' : display,
                              style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(Icons.expand_more_rounded, size: 14, color: Colors.white),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(width: 4),
                Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.person_rounded, size: 20, color: Colors.white),
                    onPressed: () => _showProfileMenu(ctx),
                  ),
                ),
                const SizedBox(width: 4),
              ],
            ),
            body: NetworkBanner(
              child: Column(
                children: [
                  _buildSearchBar(),
                  const SizedBox(height: _sectionSpacing),
                  _buildTabBar(),
                  const SizedBox(height: _sectionSpacing),
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      physics: const ClampingScrollPhysics(),
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
          ),
          // ── Vault-switching overlay ──────────────────────────────────────
          if (_switchingVault)
            Positioned.fill(
              child: Container(
                color: AppColors.primary,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.asset('assets/alignsysnew.png',
                          height: 52, fit: BoxFit.contain),
                    ),
                    const SizedBox(height: 40),
                    const SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2.5),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Switching to $_switchingVaultName',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Search bar ────────────────────────────────────────────────────────────

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
                offset: const Offset(0, 2))
          ],
        ),
        child: GestureDetector(
          onTap: () {
            _searchFocus.unfocus();
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => SearchResultsScreen(
                    initialQuery: _searchController.text.trim()),
              ),
            ).then((_) => _resetSearch());
          },
          child: AbsorbPointer(
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search...',
                hintStyle: TextStyle(color: Colors.grey.shade400),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                      color: Color.fromRGBO(25, 76, 129, 1), width: 2),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                prefixIcon: Icon(Icons.search, color: Colors.grey.shade400),
                suffixIconConstraints:
                    BoxConstraints(minHeight: 40, minWidth: hasText ? 48 : 0),
                suffixIcon: hasText
                    ? IconButton(
                        icon: Icon(Icons.close, color: Colors.grey.shade400),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                          _searchFocus.unfocus();
                        },
                      )
                    : null,
              ),
              onChanged: (v) {
                setState(() => _searchQuery = v.trim());
                if (v.trim().isNotEmpty) _executeSearch();
              },
              onSubmitted: (_) => _executeSearch(),
            ),
          ),
        ),
      ),
    );
  }

  // ── Tab bar ───────────────────────────────────────────────────────────────

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
              offset: const Offset(0, 2))
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
            color: AppColors.primary,
            borderRadius: BorderRadius.circular(8)),
        labelColor: Colors.white,
        unselectedLabelColor: Colors.grey.shade600,
        labelStyle:
            const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
        unselectedLabelStyle:
            const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
        tabs: [
          _buildTab(Icons.home_rounded, 'Home'),
          _buildTab(Icons.history_rounded, 'Recent'),
          _buildAssignedTab2(),
          _buildBadgeTab(Icons.delete_outline_rounded, 'Trash',
              (s) => s.deletedObjects.length),
          _buildBadgeTab(Icons.analytics_outlined, 'Reports',
              (s) => s.reportObjects.length),
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

  Widget _buildAssignedTab2() {
    return Consumer<MFilesService>(
      builder: (context, service, _) {
        final count = service.assignedObjects.length;
        return Tab(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.assignment_rounded, size: 16),
                    if (count > 0)
                      Positioned(
                        top: -6,
                        right: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 16),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.white, width: 1.2),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                const Text('Assigned'),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBadgeTab(
    IconData icon,
    String label,
    int Function(MFilesService) countSelector,
  ) {
    return Consumer<MFilesService>(
      builder: (context, service, _) {
        final count = countSelector(service);
        return Tab(
          height: 36,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, size: 16),
                    if (count > 0)
                      Positioned(
                        top: -6,
                        right: -8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          constraints: const BoxConstraints(minWidth: 16),
                          decoration: BoxDecoration(
                            color: Colors.red,
                            borderRadius: BorderRadius.circular(8),
                            border:
                                Border.all(color: Colors.white, width: 1.2),
                          ),
                          child: Text(
                            count > 99 ? '99+' : '$count',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 6),
                Text(label),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Tab content ───────────────────────────────────────────────────────────

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
            interactive: true,
            thickness: 6,
            radius: const Radius.circular(8),
            child: ListView(
              primary: false,
              controller: _homeScroll,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                _buildSection(
                  title: 'Common Views',
                  count: commonSorted.length,
                  expanded: _commonExpanded,
                  onToggle: () =>
                      setState(() => _commonExpanded = !_commonExpanded),
                  items: commonSorted,
                  emptyText: 'No common views',
                  leadingIcon: Icons.star_rounded,
                ),
                const SizedBox(height: 10),
                _buildSection(
                  title: 'Other Views',
                  count: otherSorted.length,
                  expanded: _otherExpanded,
                  onToggle: () =>
                      setState(() => _otherExpanded = !_otherExpanded),
                  items: otherSorted,
                  emptyText: 'No views available',
                  leadingIcon: Icons.folder_rounded,
                ),
                // Extra bottom padding so FAB doesn't overlap last row
                const SizedBox(height: 80),
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
            icon: leadingIcon),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          child: expanded
              ? Column(children: [
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
                              offset: const Offset(0, 2))
                        ],
                      ),
                      child: Column(
                          children: _buildFlatViewRows(items)),
                    ),
                ])
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [
              AppColors.primary.withOpacity(0.08),
              AppColors.primary.withOpacity(0.03),
            ]),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title,
                  style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color.fromRGBO(25, 76, 129, 1))),
            ),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12)),
              child: Text('$count',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            ),
            const SizedBox(width: 8),
            Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: AppColors.primary),
          ]),
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
              offset: const Offset(0, 2))
        ],
      ),
      child: Center(
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
                color: Colors.grey.shade100, shape: BoxShape.circle),
            child: Icon(Icons.folder_open_rounded,
                size: 32, color: Colors.grey.shade400),
          ),
          const SizedBox(height: 12),
          Text(text,
              style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 14,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  List<Widget> _buildFlatViewRows(List<ViewItem> views) {
    final rows = <Widget>[];
    for (int i = 0; i < views.length; i++) {
      rows.add(_buildFlatViewRow(views[i]));
      if (i != views.length - 1) {
        rows.add(
            Divider(height: 1, thickness: 1, color: Colors.grey.shade100));
      }
    }
    return rows;
  }

  Widget _buildFlatViewRow(ViewItem view) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          final service = context.read<MFilesService>();
          final isCommon =
              service.commonViews.any((v) => v.id == view.id);
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ViewDetailsScreen(
                view: view,
                parentSection:
                    isCommon ? 'Common Views' : 'Other Views',
              ),
            ),
          );
        },
        child: Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.grid_view_rounded,
                  size: 18, color: Color.fromRGBO(25, 76, 129, 1)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(view.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF1A1A1A))),
            ),
            if (view.count > 0) ...[
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12)),
                child: Text('${view.count}',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey.shade700)),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                size: 20, color: Colors.grey.shade400),
          ]),
        ),
      ),
    );
  }

  // ── Object-list tabs ──────────────────────────────────────────────────────

  Widget _buildRecentTab() {
    return _buildObjectList(
      selector: (s) =>
          _searchQuery.isNotEmpty ? s.searchResults : s.recentObjects,
      emptyIcon: Icons.history_rounded,
      emptyText:
          _searchQuery.isNotEmpty ? 'No results found' : 'No recent documents',
      emptySubtext: _searchQuery.isNotEmpty
          ? 'Try a different search term'
          : 'Documents you open will appear here',
      onRefresh: (s) => _searchQuery.isNotEmpty
          ? s.searchVault(_searchQuery)
          : s.fetchRecentObjects(),
      onLongPress: (obj) => showLongPressDeleteSheet(context,
          obj: obj, onDeleted: _refreshActiveTab),
    );
  }

  Widget _buildAssignedTab() {
    return _buildObjectList(
      selector: (s) => s.assignedObjects,
      emptyIcon: Icons.assignment_rounded,
      emptyText: 'No assigned items',
      emptySubtext: 'Items assigned to you will appear here',
      onRefresh: (s) => s.fetchAssignedObjects(),
      onLongPress: (obj) => showLongPressDeleteSheet(context,
          obj: obj, onDeleted: _refreshActiveTab),
    );
  }

  Widget _buildDeletedTab() {
    return _buildObjectList(
      selector: (s) => s.deletedObjects,
      emptyIcon: Icons.delete_outline_rounded,
      emptyText: 'No deleted items',
      emptySubtext: 'Deleted documents will appear here',
      onRefresh: (s) => s.fetchDeletedObjects(),
      onLongPress: (obj) => showLongPressRestoreSheet(context,
          obj: obj, onRestored: _refreshActiveTab),
    );
  }

  Widget _buildReportsTab() {
    return _buildObjectList(
      selector: (s) => s.reportObjects,
      emptyIcon: Icons.analytics_outlined,
      emptyText: 'No reports found',
      emptySubtext: 'Reports will appear here when available',
      onRefresh: (s) => s.fetchReportObjects(),
      onLongPress: (obj) => showLongPressDeleteSheet(context,
          obj: obj, onDeleted: _refreshActiveTab),
    );
  }

  Widget _buildObjectList({
    required List<ViewObject> Function(MFilesService) selector,
    required IconData emptyIcon,
    required String emptyText,
    required String emptySubtext,
    required Future<void> Function(MFilesService) onRefresh,
    required Future<void> Function(ViewObject) onLongPress,
  }) {
    return Consumer<MFilesService>(
      builder: (context, service, _) {
        final objects = selector(service);
        if (service.isLoading && objects.isEmpty) {
          return const Center(child: CircularProgressIndicator());
        }
        if (objects.isEmpty) {
          return RefreshIndicator(
            onRefresh: () => onRefresh(service),
            child: ListView(
              primary: false,
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                SizedBox(
                    height: MediaQuery.of(context).size.height * 0.18),
                _buildEmptyState(emptyIcon, emptyText, emptySubtext),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => onRefresh(service),
          child: Scrollbar(
            interactive: true,
            thickness: 6,
            radius: const Radius.circular(8),
            child: ListView.builder(
              primary: true,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(10),
              itemCount: objects.length,
              itemBuilder: (context, index) =>
                  _buildCompactObjectRow(objects[index], onLongPress),
            ),
          ),
        );
      },
    );
  }

  // ── Object row ────────────────────────────────────────────────────────────

  Widget _buildCompactObjectRow(
    ViewObject obj,
    Future<void> Function(ViewObject) onLongPress,
  ) {
    final type = obj.objectTypeName.trim();
    final idPart = obj.displayId.trim().isNotEmpty
        ? obj.displayId.trim()
        : '${obj.id}';
    final subtitle = type.isEmpty ? 'ID $idPart' : '$type | ID $idPart';
    final bool canExpand = obj.id != 0;

    final svc = context.watch<MFilesService>();
    _iconForObj(svc, obj);

    final bool isDocument = _isDocumentObj(svc, obj);
    final bool infoExpanded = _expandedInfoItemId == obj.id;
    final bool relationshipsExpanded =
        _expandedRelationshipsItemId == obj.id;
    final bool isDimmed = _expandedInfoItemId != null && !infoExpanded;

    if (canExpand &&
        !isDocument &&
        svc.cachedHasRelationships(obj.id) == null) {
      svc.ensureRelationshipsPresenceForObject(
        objectId: obj.id,
        objectTypeId: obj.objectTypeId,
        classId: obj.classId,
        notify: false,
      );
    }

    // isDeleted check: current tab is Trash (index 3)
    final bool isTrashTab = _tabController.index == 3;

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
                      offset: const Offset(0, 2))
                ]
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.05),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ],
        ),
        child: Column(children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () async {
                if (isDimmed) {
                  setState(() => _expandedInfoItemId = null);
                  return;
                }
                final deleted = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ObjectDetailsScreen(obj: obj)),
                );
                if (deleted == true) {
                  await context
                      .read<MFilesService>()
                      .fetchRecentObjects();
                }
              },
              onLongPress:
                  canLongPress(obj, context, tabs[_tabController.index])
                      ? () => onLongPress(obj)
                      : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 12),
                child: Row(children: [
                  // Relationships chevron (non-documents only)
                  if (canExpand &&
                      !isDocument &&
                      svc.cachedHasRelationships(obj.id) == true) ...[
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() {
                          if (_expandedRelationshipsItemId == obj.id) {
                            _expandedRelationshipsItemId = null;
                          } else {
                            _expandedRelationshipsItemId = obj.id;
                            _expandedInfoItemId = null;
                          }
                        }),
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

                  // Badge / icon
                  isDocument
                      ? _buildDocumentBadge(svc, obj)
                      : const Icon(Icons.folder_rounded,
                          color: AppColors.primary, size: 22),
                  const SizedBox(width: 12),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(obj.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF1A1A1A))),
                        const SizedBox(height: 4),
                        Text(subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600)),
                      ],
                    ),
                  ),

                  // Eye icon for document objects
                  if (isDocument) ...[
                    const SizedBox(width: 6),
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

                  // Info icon
                  if (canExpand) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => setState(() {
                          if (_expandedInfoItemId == obj.id) {
                            _expandedInfoItemId = null;
                          } else {
                            _expandedInfoItemId = obj.id;
                            _expandedRelationshipsItemId = null;
                          }
                        }),
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
                ]),
              ),
            ),
          ),
          if (infoExpanded && canExpand) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            ObjectInfoDropdown(
              obj: obj,
              isDeleted: isTrashTab,
            ),
          ],
          if (relationshipsExpanded && canExpand) ...[
            Divider(height: 1, color: Colors.grey.shade200),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: RelationshipsDropdown(
                  obj: obj, initiallyExpanded: true),
            ),
          ],
        ]),
      ),
    );
  }

  // ── Empty / error states ──────────────────────────────────────────────────

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
                    color: Colors.grey.shade100, shape: BoxShape.circle),
                child: Icon(icon, size: 48, color: Colors.grey.shade400)),
            const SizedBox(height: 20),
            Text(text,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A)),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(subtext,
                style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
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
                    color: Colors.red.shade50, shape: BoxShape.circle),
                child: Icon(Icons.error_outline_rounded,
                    size: 48, color: Colors.red.shade400)),
            const SizedBox(height: 20),
            const Text('Oops! Something went wrong',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1A1A1A)),
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(error,
                style:
                    TextStyle(fontSize: 14, color: Colors.grey.shade600),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  // ── Search ────────────────────────────────────────────────────────────────

  void _resetSearch({bool clearResults = true}) {
    _searchController.clear();
    _searchFocus.unfocus();
    if (mounted) setState(() => _searchQuery = '');
    if (clearResults) context.read<MFilesService>().clearSearchResults();
  }

  Future<void> _executeSearch() async {
    if (_searchQuery.isEmpty) return;
    _searchFocus.unfocus();
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SearchResultsScreen(initialQuery: _searchQuery),
      ),
    );
    _resetSearch();
  }

  // ── Create bottom sheet ───────────────────────────────────────────────────

  void _showCreateBottomSheet(BuildContext context) {
    final service = context.read<MFilesService>();
    if (service.objectTypes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'No object types available. Please wait for data to load.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    final sortedTypes = [
      ...service.objectTypes.where((t) => t.isDocument),
      ...([...service.objectTypes.where((t) => !t.isDocument)]
        ..sort((a, b) => a.displayName
            .toLowerCase()
            .compareTo(b.displayName.toLowerCase()))),
    ];

    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();

    final List<_CreateEntry> allEntries = [
      const _CreateEntry.template(),
      ...sortedTypes.map((t) => _CreateEntry.objectType(t)),
    ];
    List<_CreateEntry> filteredEntries = List.from(allEntries);
    bool showSearch = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.add_circle_outline_rounded,
                      color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Create New',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold))),
                IconButton(
                  icon: Icon(Icons.search_rounded,
                      color: showSearch
                          ? AppColors.primary
                          : Colors.grey.shade700),
                  onPressed: () {
                    setSheet(() {
                      showSearch = !showSearch;
                      if (!showSearch) {
                        searchController.clear();
                        filteredEntries = List.from(allEntries);
                      } else {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) {
                          searchFocusNode.requestFocus();
                        });
                      }
                    });
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(ctx),
                ),
              ]),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: showSearch
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search...',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14),
                            prefixIcon: Icon(Icons.search,
                                color: Colors.grey.shade400, size: 20),
                            filled: true,
                            fillColor: AppColors.surfaceLight,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade200)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade200)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 2)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            isDense: true,
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close,
                                        size: 16,
                                        color: Colors.grey.shade400),
                                    onPressed: () {
                                      searchController.clear();
                                      setSheet(() => filteredEntries =
                                          List.from(allEntries));
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (q) {
                            setSheet(() {
                              if (q.trim().isEmpty) {
                                filteredEntries = List.from(allEntries);
                              } else {
                                filteredEntries =
                                    allEntries.where((e) {
                                  if (e.isTemplate) {
                                    return 'templates'
                                        .contains(q.toLowerCase());
                                  }
                                  return e.objectType!.displayName
                                      .toLowerCase()
                                      .contains(q.toLowerCase());
                                }).toList();
                              }
                            });
                          },
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${filteredEntries.length} item${filteredEntries.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ),
              Flexible(
                child: filteredEntries.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 36,
                                  color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text('No matches found',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 13)),
                            ]),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filteredEntries.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1, color: Colors.grey.shade100),
                        itemBuilder: (context, index) {
                          final entry = filteredEntries[index];
                          if (entry.isTemplate) {
                            return Material(
                              color: Colors.transparent,
                              child: ListTile(
                                contentPadding:
                                    const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                leading: Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                      color: AppColors.primary
                                          .withOpacity(0.08),
                                      borderRadius:
                                          BorderRadius.circular(8)),
                                  child: const Icon(
                                      Icons.dashboard_customize_rounded,
                                      size: 20,
                                      color: AppColors.primary),
                                ),
                                title: const Text('Templates',
                                    style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w600)),
                                subtitle: Text(
                                    'Create from a pre-defined template',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade500)),
                                trailing: Icon(
                                    Icons.chevron_right_rounded,
                                    color: Colors.grey.shade400),
                                onTap: () {
                                  Navigator.pop(ctx);
                                  _showTemplateClassPicker();
                                },
                              ),
                            );
                          }
                          final ot = entry.objectType!;
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withOpacity(0.08),
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                child: Icon(
                                  ot.isDocument
                                      ? Icons.description_rounded
                                      : _iconForObjectTypeName(
                                          ot.displayName),
                                  size: 20,
                                  color: AppColors.primary,
                                ),
                              ),
                              title: Text(ot.displayName,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.grey.shade400),
                              onTap: () {
                                Navigator.pop(ctx);
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                      builder: (_) => DynamicFormScreen(
                                          objectType: ot)),
                                );
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Template class picker ─────────────────────────────────────────────────

  void _showTemplateClassPicker() => _loadClassesWithTemplates();

  List<ObjectClass> _collectAllClasses(MFilesService service) {
    final seen = <int>{};
    final result = <ObjectClass>[];
    for (final ot in service.objectTypes) {
      for (final group in service.getClassGroupsForType(ot.id)) {
        for (final cls in group.members) {
          if (seen.add(cls.id)) result.add(cls);
        }
      }
    }
    if (result.isEmpty) {
      for (final cls in service.objectClasses) {
        if (seen.add(cls.id)) result.add(cls);
      }
    }
    result.sort((a, b) => a.displayName
        .toLowerCase()
        .compareTo(b.displayName.toLowerCase()));
    return result;
  }

  Future<void> _loadClassesWithTemplates() async {
    if (!mounted) return;
    final service = context.read<MFilesService>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      if (service.objectTypes.isEmpty) await service.fetchObjectTypes();
      await Future.wait(
          service.objectTypes.map((ot) => service.fetchObjectClasses(ot.id)));

      final vaultGuid = service.selectedVault?.guid ?? '';

      final allTemplates =
          await service.fetchAllTemplates(vaultGuid: vaultGuid);

      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();

      if (allTemplates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No templates found in this repository.')));
        return;
      }

      final Map<int, List<Map<String, dynamic>>> templatesByClass = {};
      for (final t in allTemplates) {
        final classId = (t['classId'] ??
            t['classID'] ??
            t['ClassID'] ??
            t['ClassId']) as int?;
        if (classId == null) continue;
        templatesByClass.putIfAbsent(classId, () => []).add(t);
      }

      final allClasses = _collectAllClasses(service);
      final classesWithTemplates = allClasses
          .where((cls) => templatesByClass.containsKey(cls.id))
          .toList();

      if (classesWithTemplates.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('No templates found in this repository.')));
        return;
      }

      _openTemplateClassSheet(
        classesWithTemplates,
        templatesByClass: templatesByClass,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to load templates: $e'),
        backgroundColor: Colors.red,
      ));
    }
  }

  void _openTemplateClassSheet(
    List<ObjectClass> allClasses, {
    required Map<int, List<Map<String, dynamic>>> templatesByClass,
  }) {
    if (!mounted) return;
    final searchController = TextEditingController();
    final searchFocusNode = FocusNode();
    List<ObjectClass> filtered = List.from(allClasses);
    bool showSearch = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheet) => Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.vertical(top: Radius.circular(20)),
          ),
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 14,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2))),
              const SizedBox(height: 20),
              Row(children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.dashboard_customize_rounded,
                      color: AppColors.primary, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text('Select Template',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold))),
                IconButton(
                  icon: Icon(Icons.search_rounded,
                      color: showSearch
                          ? AppColors.primary
                          : Colors.grey.shade700),
                  onPressed: () {
                    setSheet(() {
                      showSearch = !showSearch;
                      if (!showSearch) {
                        searchController.clear();
                        filtered = List.from(allClasses);
                      } else {
                        WidgetsBinding.instance
                            .addPostFrameCallback((_) {
                          searchFocusNode.requestFocus();
                        });
                      }
                    });
                  },
                ),
                IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx)),
              ]),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                child: showSearch
                    ? Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: TextField(
                          controller: searchController,
                          focusNode: searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search templates...',
                            hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14),
                            prefixIcon: Icon(Icons.search,
                                color: Colors.grey.shade400, size: 20),
                            filled: true,
                            fillColor: AppColors.surfaceLight,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade200)),
                            enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: BorderSide(
                                    color: Colors.grey.shade200)),
                            focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(12),
                                borderSide: const BorderSide(
                                    color: AppColors.primary, width: 2)),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 12),
                            isDense: true,
                            suffixIcon: searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close,
                                        size: 16,
                                        color: Colors.grey.shade400),
                                    onPressed: () {
                                      searchController.clear();
                                      setSheet(() => filtered =
                                          List.from(allClasses));
                                    },
                                  )
                                : null,
                          ),
                          onChanged: (q) {
                            setSheet(() {
                              filtered = q.trim().isEmpty
                                  ? List.from(allClasses)
                                  : allClasses
                                      .where((c) => c.displayName
                                          .toLowerCase()
                                          .contains(q.toLowerCase()))
                                      .toList();
                            });
                          },
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '${filtered.length} template${filtered.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12, color: Colors.grey.shade500),
                  ),
                ),
              ),
              Flexible(
                child: filtered.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.search_off,
                                  size: 36,
                                  color: Colors.grey.shade300),
                              const SizedBox(height: 8),
                              Text('No matches found',
                                  style: TextStyle(
                                      color: Colors.grey.shade500,
                                      fontSize: 13)),
                            ]),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => Divider(
                            height: 1, color: Colors.grey.shade100),
                        itemBuilder: (_, index) {
                          final cls = filtered[index];
                          return Material(
                            color: Colors.transparent,
                            child: ListTile(
                              contentPadding:
                                  const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                              leading: Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                    color: AppColors.primary
                                        .withOpacity(0.08),
                                    borderRadius:
                                        BorderRadius.circular(8)),
                                child: const Icon(
                                    Icons.dashboard_customize_rounded,
                                    size: 20,
                                    color: AppColors.primary),
                              ),
                              title: Text(cls.displayName,
                                  style: const TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600)),
                              trailing: Icon(
                                  Icons.chevron_right_rounded,
                                  color: Colors.grey.shade400),
                              onTap: () {
                                Navigator.pop(ctx);
                                final templates =
                                    templatesByClass[cls.id] ?? [];
                                _openTemplateDocumentSheetDirect(
                                    cls, templates);
                              },
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openTemplateDocumentSheetDirect(
      ObjectClass cls, List<Map<String, dynamic>> templates) {
    if (!mounted) return;

    if (templates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('No templates available for ${cls.displayName}.'),
        backgroundColor: Colors.orange,
      ));
      return;
    }

    if (templates.length == 1) {
      final t = templates.first;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => TemplateFormScreen(
            classId: cls.id,
            className: cls.displayName,
            templateObjectId: t['id'] as int,
            templateTitle: t['title'] as String? ?? 'Template',
          ),
        ),
      );
      return;
    }

    _openTemplateDocumentSheet(cls, templates);
  }

  void _openTemplateDocumentSheet(
      ObjectClass cls, List<Map<String, dynamic>> templates) {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius:
              BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 14,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 20),
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.description_rounded,
                    color: AppColors.primary, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Choose Template',
                        style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold)),
                    Text(cls.displayName,
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500)),
                  ],
                ),
              ),
              IconButton(
                  icon: const Icon(Icons.close, color: Colors.grey),
                  onPressed: () => Navigator.pop(context)),
            ]),
            const SizedBox(height: 12),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: templates.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade100),
                itemBuilder: (ctx, index) {
                  final t = templates[index];
                  final title = t['title'] as String? ?? 'Untitled';
                  final modified = t['lastModifiedUtc'] as String?;
                  String? dateStr;
                  if (modified != null) {
                    try {
                      final dt = DateTime.parse(modified);
                      dateStr =
                          '${dt.day} ${_monthName(dt.month)} ${dt.year}';
                    } catch (_) {}
                  }
                  return Material(
                    color: Colors.transparent,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 6),
                      leading: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                            color:
                                AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.description_rounded,
                            size: 20,
                            color: Color.fromRGBO(25, 76, 129, 1)),
                      ),
                      title: Text(title,
                          style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600)),
                      subtitle: dateStr != null
                          ? Text(dateStr,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade500))
                          : null,
                      trailing: Icon(Icons.chevron_right_rounded,
                          color: Colors.grey.shade400),
                      onTap: () {
                        Navigator.pop(ctx);
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => TemplateFormScreen(
                              classId: cls.id,
                              className: cls.displayName,
                              templateObjectId: t['id'] as int,
                              templateTitle: title,
                            ),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  String _monthName(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ][m];

  // ── Vault switcher ─────────────────────────────────────────────────────────
  void _showVaultSwitcher(BuildContext context) {
  final service = context.read<MFilesService>();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
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
            Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storage_rounded,
                    color: AppColors.primary, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Switch Repository',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Select a vault to work in',
                      style: TextStyle(
                          fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: Colors.grey.shade500),
                onPressed: () => Navigator.pop(context),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ]),
            const SizedBox(height: 20),
            Divider(height: 1, color: Colors.grey.shade100),
            const SizedBox(height: 12),
            // Vault list
            FutureBuilder<List<Vault>>(
              future: service.getUserVaults(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Error loading repositories: ${snapshot.error}',
                      style: TextStyle(
                          color: Colors.red.shade700, fontSize: 13),
                    ),
                  );
                }
                final vaults = snapshot.data ?? [];
                if (vaults.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: Text(
                        'No repositories available',
                        style: TextStyle(
                            color: Colors.grey.shade500, fontSize: 13),
                      ),
                    ),
                  );
                }
                final selectedGuid = service.selectedVault?.guid;
                return Column(
                  children: vaults.map((v) {
                    final isSelected = v.guid == selectedGuid;
                    return Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: isSelected
                            ? null
                            : () async {
                                Navigator.pop(context);
                                setState(() {
                                  _switchingVault = true;
                                  _switchingVaultName = v.name;
                                });
                                try {
                                  await service.saveSelectedVault(v);
                                  await service.fetchMFilesUserId();
                                  await service.fetchObjectTypes();
                                  await service.fetchAllViews();
                                  await Future.wait([
                                    service.fetchRecentObjects(),
                                    service.fetchDeletedObjects(),
                                    service.fetchAssignedObjects(),
                                    service.fetchReportObjects(),
                                  ]);
                                } finally {
                                  if (mounted) {
                                    setState(() => _switchingVault = false);
                                  }
                                }
                              },
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary.withOpacity(0.06)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary.withOpacity(0.3)
                                  : Colors.grey.shade200,
                              width: isSelected ? 1.5 : 1,
                            ),
                          ),
                          child: Row(children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? AppColors.primary.withOpacity(0.12)
                                    : Colors.grey.shade100,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Icon(
                                  Icons.storage_rounded,
                                  size: 17,
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                v.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: isSelected
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: isSelected
                                      ? AppColors.primary
                                      : const Color(0xFF1E293B),
                                ),
                              ),
                            ),
                            if (isSelected)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: const Text(
                                  'Active',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: AppColors.primary,
                                  ),
                                ),
                              )
                            else
                              Icon(Icons.chevron_right_rounded,
                                  size: 18, color: Colors.grey.shade400),
                          ]),
                        ),
                      ),
                    );
                  }).toList(),
                );
              },
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    ),
  );
}

  // ── Profile menu ──────────────────────────────────────────────────────────
  void _showProfileMenu(BuildContext context) {
    final service = context.read<MFilesService>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 24),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              // ── User header ──────────────────────────────────────────────
              Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: Icon(Icons.person_rounded,
                        color: AppColors.primary, size: 24),
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
                            fontSize: 16, fontWeight: FontWeight.w700),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        service.userEmail ?? 'No email on file',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey.shade500),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ]),

              const SizedBox(height: 20),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 12),
              
              // ── Active vault display ───────────────────────────────────
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2),
                      width: 1.5),
                ),
                child: Row(children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Center(
                      child: Icon(Icons.storage_rounded,
                          size: 16, color: AppColors.primary),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      service.selectedVault?.name ?? 'No vault selected',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'Active',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ]),
              ),

              const SizedBox(height: 8),

              // ── Switch repository shortcut ───────────────────────────────
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(context);
                    _showVaultSwitcher(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(Icons.swap_horiz_rounded,
                              size: 16, color: Colors.grey.shade600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Switch repository',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: Colors.grey.shade400),
                    ]),
                  ),
                ),
              ),

              const SizedBox(height: 16),
              Divider(height: 1, color: Colors.grey.shade100),
              const SizedBox(height: 8),

              // ── Log out ──────────────────────────────────────────────────
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () {
                    Navigator.pop(context);
                    _handleLogout(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.red.shade100),
                    ),
                    child: Row(children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Colors.red.shade100,
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Icon(Icons.logout_rounded,
                              size: 16, color: Colors.red.shade600),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Log out',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.red.shade700,
                          ),
                        ),
                      ),
                      Icon(Icons.chevron_right_rounded,
                          size: 18, color: Colors.red.shade300),
                    ]),
                  ),
                ),
              ),

              const SizedBox(height: 4),
            ],
          ),
        ),
      ),
    );
  }

  void _handleLogout(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        title: const Text('Log Out',
            style: TextStyle(fontWeight: FontWeight.bold)),
        content: const Text('Are you sure you want to log out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel',
                style: TextStyle(color: Colors.grey.shade700)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
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

// ── Create entry type ─────────────────────────────────────────────────────────

class _CreateEntry {
  final bool isTemplate;
  final VaultObjectType? objectType;

  const _CreateEntry.template()
      : isTemplate = true,
        objectType = null;

  const _CreateEntry.objectType(VaultObjectType type)
      : isTemplate = false,
        objectType = type;
}