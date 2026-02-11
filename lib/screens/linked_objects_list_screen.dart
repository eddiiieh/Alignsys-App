import 'package:flutter/material.dart';
import 'package:mfiles_app/models/view_object.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:mfiles_app/widgets/relationships_dropdown.dart';
import 'package:mfiles_app/models/linked_object_item.dart';

class LinkedObjectsListScreen extends StatefulWidget {
  final String title;
  final List<LinkedObjectItem> items;
  const LinkedObjectsListScreen({super.key, required this.title, required this.items});

  @override
  State<LinkedObjectsListScreen> createState() => _LinkedObjectsListScreenState();
}

class _LinkedObjectsListScreenState extends State<LinkedObjectsListScreen> {
  final ScrollController _sc = ScrollController();

  @override
  void dispose() {
    _sc.dispose();
    super.dispose();
  }

  ViewObject _toViewObject(LinkedObjectItem it) {
    return ViewObject(
      id: it.id,                 // object id
      title: it.title,
      objectTypeId: it.objectID, // object type id
      classId: it.classID,
      versionId: 0,              // not needed
      objectTypeName: it.objectTypeName,
      classTypeName: it.classTypeName,
      displayId: it.displayID,
      createdUtc: null,
      lastModifiedUtc: null,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: const Color(0xFF072F5F),
        foregroundColor: Colors.white,
        title: Text(widget.title),
        ),
      body: Scrollbar(
        controller: _sc,
        thumbVisibility: false,
        interactive: true,
        thickness: 4,
        radius: const Radius.circular(8),
        child: ListView.separated(
          controller: _sc,
          padding: const EdgeInsets.all(16),
          itemCount: widget.items.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
          final it = widget.items[i];
          final obj = _toViewObject(it);

          return Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                trailing: const Icon(Icons.expand_more, size: 18),
                title: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => ObjectDetailsScreen(obj: obj)),
                    );
                  },
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
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              obj.objectTypeName.isNotEmpty ? obj.objectTypeName : obj.classTypeName,
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
                children: [
                  RelationshipsDropdown(obj: obj),
                ],
              ),
            ),
          );
        },
      ),
      ),
    );
  }
}
