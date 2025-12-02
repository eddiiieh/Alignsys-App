import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../models/vault.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<int, bool> _expandedTypes = {};
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MFilesService>().fetchObjectTypes();
    });
  }

  void _showProfileMenu(BuildContext context) {
    final service = context.read<MFilesService>();
    final RenderBox button = context.findRenderObject() as RenderBox;
    final RenderBox overlay = Navigator.of(context).overlay!.context.findRenderObject() as RenderBox;
    final buttonPosition = button.localToGlobal(Offset.zero, ancestor: overlay);
    
    // Position the menu directly below the profile icon, aligned to the right
    final RelativeRect position = RelativeRect.fromLTRB(
      buttonPosition.dx + button.size.width - 220, // 280 is menu width, align right edge
      buttonPosition.dy + button.size.height, // directly below the button
      0,
      0,
    );

    showMenu<String>(
      context: context,
      position: position,
      color: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      elevation: 8,
      constraints: const BoxConstraints(
        minWidth: 220,
        maxWidth: 220,
      ),
      items: [
        // Email Section
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.person, size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
                  const SizedBox(width: 8),
                  const Text(
                    'Account',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                service.username ?? 'Unknown',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Divider(height: 16),
            ],
          ),
        ),
        
        // Vault Selection Section
        PopupMenuItem<String>(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.storage, size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
                  const SizedBox(width: 8),
                  const Text(
                    'Current Vault',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                service.selectedVault?.name ?? 'None',
                style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black87,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        
        // Switch Vault Option
        PopupMenuItem<String>(
          value: 'switch_vault',
          child: const Row(
            children: [
              Icon(Icons.swap_horiz, size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
              SizedBox(width: 12),
              Text('Switch Vault'),
            ],
          ),
        ),
        
        const PopupMenuDivider(),
        
        // Logout Option
        PopupMenuItem<String>(
          value: 'logout',
          child: const Row(
            children: [
              Icon(Icons.logout, size: 20, color: Colors.red),
              SizedBox(width: 12),
              Text(
                'Log Out',
                style: TextStyle(color: Colors.red),
              ),
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
                child: Center(child: CircularProgressIndicator()),
              );
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
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected 
                            ? const Color.fromRGBO(25, 76, 129, 1)
                            : Colors.black87,
                      ),
                    ),
                    trailing: isSelected 
                        ? const Icon(
                            Icons.check_circle,
                            color: Color.fromRGBO(25, 76, 129, 1),
                          )
                        : null,
                    onTap: isSelected
                        ? null
                        : () async {
                            Navigator.pop(context);
                            service.selectedVault = vault;
                            await service.fetchObjectTypes();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Switched to ${vault.name}'),
                                  backgroundColor: const Color.fromRGBO(25, 76, 129, 1),
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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(52),
          child: AppBar(
            backgroundColor: const Color.fromARGB(255, 251, 251, 251),
            elevation: 0,
            titleSpacing: 0,
            title: Row(
              children: [
                // Alignsys logo
                Padding(
                  padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Image.asset(
                      'assets/alignsyslogo.png',
                      height: 32,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),            
              ],
            ),
            actions: [
              // New button
              TextButton.icon(
                style: TextButton.styleFrom(
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
                onPressed: () {
                  Navigator.pushNamed(context, '/new');
                },
                icon: const Icon(Icons.add, size: 20, color: Color.fromRGBO(25, 76, 129, 1)),
                label: const Text(
                  'Create',
                  style: TextStyle(fontSize: 14, color: Color.fromRGBO(25, 76, 129, 1)),
                ),
              ),
              const SizedBox(width: 0),
              // Profile button with dropdown menu
              Builder(
                builder: (BuildContext context) {
                  return IconButton(
                    icon: const Icon(Icons.person, color: Color.fromRGBO(25, 76, 129, 1)),
                    onPressed: () => _showProfileMenu(context),
                  );
                },
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),

        body: Consumer<MFilesService>(
          builder: (context, service, child) {
            if (service.isLoading && service.objectTypes.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (service.error != null && service.objectTypes.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Error: ${service.error}',
                      style: const TextStyle(color: Colors.red),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () {
                        service.clearError();
                        service.fetchObjectTypes();
                      },
                      child: const Text('Retry'),
                    ),
                  ],
                ),
              );
            }

            final filteredObjectTypes = service.objectTypes
                .where((type) => type.displayName.toLowerCase().contains(_searchQuery.toLowerCase()))
                .toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Search
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search object or object class...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                    ),
                    onChanged: (value) {
                      setState(() {
                        _searchQuery = value;
                      });
                    },
                  ),
                ),

                // --- USER INFO CARD ---
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'User: ${service.username ?? "Unknown"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Vault: ${service.selectedVault?.name ?? "None"}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),

                // --- OBJECT TYPES ---
                ExpansionTile(
                  leading: const Icon(Icons.folder, color: Colors.blue),
                  title: const Text(
                    "Object Types",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  children: filteredObjectTypes.map((objectType) {
                    final isExpanded = _expandedTypes[objectType.id] ?? false;
                    final objectClasses = service.objectClasses
                        .where((cls) => cls.objectTypeId == objectType.id)
                        .toList();

                    return ExpansionTile(
                      key: ValueKey(objectType.id),
                      title: Text(objectType.displayName),
                      subtitle: Text('ID: ${objectType.id}'),
                      leading: Icon(
                        objectType.isDocument ? Icons.description : Icons.folder,
                        color: Colors.blue,
                      ),
                      initiallyExpanded: isExpanded,
                      onExpansionChanged: (expanded) async {
                        setState(() {
                          _expandedTypes[objectType.id] = expanded;
                        });

                        if (expanded && objectClasses.isEmpty) {
                          await context.read<MFilesService>().fetchObjectClasses(objectType.id);
                        }
                      },
                      children: [
                        // Ungrouped classes
                        if (service.objectClasses
                            .where((cls) => cls.objectTypeId == objectType.id)
                            .any((cls) => !service.isClassInAnyGroup(cls.id)))
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 4.0),
                            child: Text(
                              'General',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ...service.objectClasses
                            .where((cls) => cls.objectTypeId == objectType.id)
                            .where((cls) => !service.isClassInAnyGroup(cls.id))
                            .map((cls) => ListTile(
                                  leading: const Icon(Icons.folder_open, color: Colors.green),
                                  title: Text(cls.displayName),
                                  subtitle: Text('Class ID: ${cls.id}'),
                                  onTap: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (_) => DynamicFormScreen(
                                          objectType: objectType,
                                          objectClass: cls,
                                        ),
                                      ),
                                    );
                                  },
                                ))
                            .toList(),
                        // Grouped classes
                        ...service.getClassGroupsForType(objectType.id).map((group) => Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: const EdgeInsets.only(left: 16.0, top: 8.0),
                                  child: Text(
                                    group.classGroupName,
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                ),
                                ...group.members.map((cls) => ListTile(
                                      leading: const Icon(Icons.folder_open, color: Colors.green),
                                      title: Text(cls.displayName),
                                      subtitle: Text('Class ID: ${cls.id}'),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (_) => DynamicFormScreen(
                                              objectType: objectType,
                                              objectClass: cls,
                                            ),
                                          ),
                                        );
                                      },
                                    )),
                              ],
                            )),
                      ],
                    );
                  }).toList(),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}