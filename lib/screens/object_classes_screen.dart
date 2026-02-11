import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../models/vault_object_type.dart';
import '../models/object_class.dart';
import 'dynamic_form_screen.dart';

class ObjectClassesScreen extends StatefulWidget {
  final VaultObjectType objectType;
  final ObjectClass? preselectedClass;

  const ObjectClassesScreen({
    super.key,
    required this.objectType,
    this.preselectedClass,
  });

  @override
  State<ObjectClassesScreen> createState() => _ObjectClassesScreenState();
}

class _ObjectClassesScreenState extends State<ObjectClassesScreen> {

  final ScrollController _classesScroll = ScrollController();

  @override
  void initState() {
    _classesScroll.dispose();
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<MFilesService>().fetchObjectClasses(widget.objectType.id);

      if (widget.preselectedClass != null) {
      // Navigate directly to form if class is preselected
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DynamicFormScreen(
            objectType: widget.objectType,
            objectClass: widget.preselectedClass!,
          ),
        ),
      );
    }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Object Classes - ${widget.objectType.displayName}'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Consumer<MFilesService>(
        builder: (context, service, child) {
          if (service.isLoading && service.objectClasses.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (service.error != null && service.objectClasses.isEmpty) {
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
                      service.fetchObjectClasses(widget.objectType.id);
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          final objectClasses = service.objectClasses
              .where((cls) => cls.objectTypeId == widget.objectType.id)
              .toList();

          return Scrollbar(
            controller: _classesScroll,
            thumbVisibility: false,
            interactive: true,
            thickness: 4,
            radius: const Radius.circular(8),
            child: ListView(
              controller: _classesScroll,
            padding: const EdgeInsets.all(16),
            children: [
              ListTile(
                leading: const Icon(Icons.add, color: Colors.green),
                title: const Text(
                  'Create New Object Class',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                tileColor: Colors.green.shade50,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => DynamicFormScreen(
                        objectType: widget.objectType,
                        objectClass: widget.preselectedClass!,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 16),
              ...objectClasses.map((objectClass) => Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    child: ListTile(
                      leading: const Icon(Icons.folder_open),
                      title: Text(
                        objectClass.displayName,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('Class ID: ${objectClass.id}'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DynamicFormScreen(
                              objectType: widget.objectType,
                              objectClass: objectClass,
                            ),
                          ),
                        );
                      },
                    ),
                  )),
            ],
            ),
          );
        },
      ),
    );
  }
}
