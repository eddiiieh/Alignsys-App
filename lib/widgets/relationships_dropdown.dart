import 'package:flutter/material.dart';
import 'package:mfiles_app/models/linked_object_item.dart';
import 'package:mfiles_app/screens/linked_objects_list_screen.dart';
import 'package:provider/provider.dart';
import '../models/view_object.dart';
import '../services/mfiles_service.dart';

class RelationshipsDropdown extends StatefulWidget {
  final ViewObject obj;

  /// optional: collapsed by default
  final bool initiallyExpanded;

  const RelationshipsDropdown({
    super.key,
    required this.obj,
    this.initiallyExpanded = false,
  });

  @override
  State<RelationshipsDropdown> createState() => _RelationshipsDropdownState();
}

class _RelationshipsDropdownState extends State<RelationshipsDropdown> {
  Future<List<LinkedObjectsGroup>>? _future;
  bool _loaded = false;

    void _loadOnce() {
    if (_loaded) return;
    _loaded = true;

    final s = context.read<MFilesService>();
    _future = s.fetchLinkedObjects(
      vaultGuid: s.vaultGuidWithBraces,
      objectTypeId: widget.obj.objectTypeId,
      objectId: widget.obj.id,
      classId: widget.obj.classId,
      userId: s.currentUserId,
    );
  }

  @override
  Widget build(BuildContext context) {
    // if object id missing, fail fast
    if (widget.obj.id == 0 || widget.obj.objectTypeId == 0 || widget.obj.classId == 0) {
      return Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          'No relationships available.',
          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: widget.initiallyExpanded,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: const Text(
            'Relationships',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
          ),
          onExpansionChanged: (expanded) {
            if (expanded) setState(_loadOnce);
          },
          children: [
            if (_future == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Expand to load…'),
              )
            else
              FutureBuilder(
                future: _future,
                builder: (context, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Padding(
                      padding: EdgeInsets.all(12),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snap.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text('Failed: ${snap.error}'),
                    );
                  }

                  final groups = snap.data ?? const <LinkedObjectsGroup>[];
                  if (groups.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No relationships found.',
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    );
                  }

                  return Column(
                    children: groups.map((g) {
                      final propertyName = g.propertyName;
                      final items = g.items;

                      return Container(
                        margin: const EdgeInsets.only(top: 8),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.grey.shade200),
                        ),
                        child: ListTile(
                          dense: true,
                          title: Text(propertyName, style: const TextStyle(fontWeight: FontWeight.w600)),
                          trailing: Text('(${items.length})'),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LinkedObjectsListScreen(
                                  title: propertyName,
                                  items: items,
                                ),
                              ),
                            );
                          },
                        ),
                      );
                    }).toList(),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }
}

class _LinkedObjectsListScreen extends StatelessWidget {
  final String title;
  final List items;

  const _LinkedObjectsListScreen({required this.title, required this.items});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: ListView.separated(
        itemCount: items.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (context, i) {
          final it = items[i] as dynamic;
          return ListTile(
            title: Text((it.title ?? '').toString()),
            subtitle: Text('${(it.objectTypeName ?? '')} • ${(it.displayID ?? '')}'),
            onTap: () {
              // next step: open object details for this linked item
              // you need a method that fetches object details by (objectTypeId=it.objectID, objectId=it.id)
            },
          );
        },
      ),
    );
  }
}
