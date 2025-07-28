import 'package:flutter/material.dart';
import 'package:mfiles_app/screens/dynamic_form_screen.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';

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

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: PreferredSize(
          preferredSize: const Size.fromHeight(52), // Reduced height
          child: AppBar(
            backgroundColor: const Color(0xFF0A1541), // Custom dark blue
            elevation: 0,
            titleSpacing: 0,
            title: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 12.0, right: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: Image.asset(
                      'assets/mfileslogo.png',
                      height: 36,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 6.0),
                  child: Text(
                    '|',
                    style: TextStyle(
                      color: Colors.grey,
                      fontWeight: FontWeight.bold,
                      fontSize: 22,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/TechEdgeLogo.png',
                      height: 30,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12.0),
                child: OutlinedButton.icon(
                  onPressed: () {
                    // Add your "New" action here
                  },
                  icon: const Icon(Icons.add, color: Colors.white, size: 20),
                  label: const Text(
                    'New',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    backgroundColor: const Color(0xFF0A1541),
                    side: BorderSide.none,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    textStyle: const TextStyle(fontSize: 14),
                  ),
                ),
              ),
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

            final filteredObjectTypes = service.objectTypes.where((type) =>
                type.displayName.toLowerCase().contains(_searchQuery.toLowerCase())).toList();

            return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: TextField(
                    decoration: InputDecoration(
                      hintText: 'Search object or object class...',
                      prefixIcon: Icon(Icons.search),
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
                        // First show ungrouped classes
                        if (service.objectClasses
                            .where((cls) => cls.objectTypeId == objectType.id)
                            .any((cls) => !service.isClassInAnyGroup(cls.id)))
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 16.0, top: 8.0, bottom: 4.0),
                              child: Text(
                                'General',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14, // Optional: adjust font size if needed
                                ),
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
                            )).toList(),
                            // Then show grouped classes
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
                                )).toList(),
                              ],
                            )).toList(),
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