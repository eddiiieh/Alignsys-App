import 'package:flutter/material.dart';
import 'package:mfiles_app/models/linked_object_item.dart';
import 'package:mfiles_app/screens/object_details_screen.dart';
import 'package:provider/provider.dart';
import '../models/view_object.dart';
import '../services/mfiles_service.dart';

class RelationshipsDropdown extends StatefulWidget {
  final ViewObject obj;
  final bool initiallyExpanded;

  // Only root shows "Relationships"
  final bool isRoot;

  // Indentation / subtle tree styling
  final int depth;

  const RelationshipsDropdown({
    super.key,
    required this.obj,
    this.initiallyExpanded = false,
    this.isRoot = true,
    this.depth = 0,
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
    final left = 8.0 + (widget.depth * 14.0);

    // Missing identity payload: just show a small message (no header if nested)
    final missingIdentity =
        widget.obj.id == 0 || widget.obj.objectTypeId == 0 || widget.obj.classId == 0;

    if (missingIdentity) {
      return Padding(
        padding: EdgeInsets.fromLTRB(left, 6, 12, 6),
        child: Text(
          widget.isRoot ? 'No relationships.' : 'No linked items.',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      );
    }

    // Root: show a small header row + collapsible content
    if (widget.isRoot) {
      return _RootRelationshipsSection(
        titleLeftPadding: left,
        initiallyExpanded: widget.initiallyExpanded,
        child: _GroupsBody(
          depth: widget.depth,
          future: _future,
          loaded: _loaded,
          onLoad: () => setState(_loadOnce),
        ),
      );
    }

    // Nested: no "Relationships" label at all—just render groups
    return _GroupsBody(
      depth: widget.depth,
      future: _future,
      loaded: _loaded,
      onLoad: () => setState(_loadOnce),
    );
  }
}

class _RootRelationshipsSection extends StatefulWidget {
  final double titleLeftPadding;
  final bool initiallyExpanded;
  final Widget child;

  const _RootRelationshipsSection({
    required this.titleLeftPadding,
    required this.initiallyExpanded,
    required this.child,
  });

  @override
  State<_RootRelationshipsSection> createState() => _RootRelationshipsSectionState();
}

class _RootRelationshipsSectionState extends State<_RootRelationshipsSection> {
  late bool _open;

  @override
  void initState() {
    super.initState();
    _open = widget.initiallyExpanded;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: EdgeInsets.fromLTRB(widget.titleLeftPadding, 10, 12, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Relationships',
                    style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
                  ),
                ),
                Icon(
                  _open ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                  color: Colors.grey.shade700,
                ),
              ],
            ),
          ),
        ),
        AnimatedCrossFade(
          firstChild: const SizedBox.shrink(),
          secondChild: widget.child,
          crossFadeState: _open ? CrossFadeState.showSecond : CrossFadeState.showFirst,
          duration: const Duration(milliseconds: 160),
        ),
      ],
    );
  }
}

class _GroupsBody extends StatelessWidget {
  final Future<List<LinkedObjectsGroup>>? future;
  final VoidCallback onLoad;
  final int depth;
  final bool loaded;

  const _GroupsBody({
    required this.future,
    required this.onLoad,
    required this.depth,
    required this.loaded,
  });

  @override
  Widget build(BuildContext context) {
    final left = 8.0 + (depth * 14.0);

    // Lazy load the first time this subtree appears (no "Expand to load…" text)
    if (!loaded) {
      WidgetsBinding.instance.addPostFrameCallback((_) => onLoad());
    }

    if (future == null) {
      return Padding(
        padding: EdgeInsets.fromLTRB(left, 6, 12, 10),
        child: const LinearProgressIndicator(minHeight: 2),
      );
    }

    return FutureBuilder<List<LinkedObjectsGroup>>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Padding(
            padding: EdgeInsets.fromLTRB(left, 6, 12, 10),
            child: const LinearProgressIndicator(minHeight: 2),
          );
        }

        if (snap.hasError) {
          // Keep this subtle; don't scream red blocks
          return Padding(
            padding: EdgeInsets.fromLTRB(left, 6, 12, 10),
            child: Text(
              'Failed to load relationships.',
              style: TextStyle(fontSize: 12, color: Colors.red.shade700),
            ),
          );
        }

        final groups = snap.data ?? const <LinkedObjectsGroup>[];
        if (groups.isEmpty) {
          return Padding(
            padding: EdgeInsets.fromLTRB(left, 6, 12, 10),
            child: Text(
              'No relationships found.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          );
        }

        return Column(
          children: groups
              .where((g) => g.items.isNotEmpty)
              .map(
                (g) => _RelationshipGroupTileModern(
                  propertyName: g.propertyName,
                  items: g.items,
                  depth: depth,
                ),
              )
              .toList(),
        );
      },
    );
  }
}

ViewObject _toViewObjectFromLinked(LinkedObjectItem it) {
  return ViewObject(
    id: it.id,
    title: it.title,
    objectTypeId: it.objectID,
    classId: it.classID,
    versionId: 0,
    objectTypeName: it.objectTypeName,
    classTypeName: it.classTypeName,
    displayId: it.displayID,
    createdUtc: null,
    lastModifiedUtc: null,
  );
}

/// Modern: thin rows, minimal chrome, subtle count, tree guide line.
class _RelationshipGroupTileModern extends StatelessWidget {
  final String propertyName;
  final List<LinkedObjectItem> items;
  final int depth;

  const _RelationshipGroupTileModern({
    required this.propertyName,
    required this.items,
    required this.depth,
  });

  @override
  Widget build(BuildContext context) {
    final left = 8.0 + (depth * 14.0);

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.fromLTRB(left, 2, 8, 2),
        childrenPadding: EdgeInsets.fromLTRB(left + 12, 0, 8, 6),
        title: Row(
          children: [
            Icon(Icons.link, size: 18, color: Colors.grey.shade700),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                propertyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${items.length}',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
          ],
        ),
        children: [
          Container(
            margin: const EdgeInsets.only(left: 6),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: Colors.grey.shade300, width: 1)),
            ),
            child: Column(
              children: items.map((it) => _LinkedObjectNodeTileModern(item: it, depth: depth + 1)).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

class _LinkedObjectNodeTileModern extends StatelessWidget {
  final LinkedObjectItem item;
  final int depth;

  const _LinkedObjectNodeTileModern({required this.item, required this.depth});

  @override
  Widget build(BuildContext context) {
    final obj = _toViewObjectFromLinked(item);
    final canExpand = obj.id != 0 && obj.objectTypeId != 0 && obj.classId != 0;

    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.fromLTRB(10, 2, 6, 2),
        childrenPadding: const EdgeInsets.only(left: 6, right: 6, bottom: 6),
        enabled: true, // do not dim the whole tile
        trailing: canExpand ? const Icon(Icons.expand_more, size: 18) : const SizedBox(width: 18),
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ObjectDetailsScreen(obj: obj)),
            );
          },
          child: Row(
            children: [
              const Icon(Icons.folder_outlined, size: 18, color: Color.fromRGBO(25, 76, 129, 1)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      obj.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${obj.objectTypeName} • ${obj.displayId}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        children: canExpand
            ? [
                RelationshipsDropdown(
                  obj: obj,
                  initiallyExpanded: false,
                  isRoot: false, // IMPORTANT: no repeated "Relationships"
                  depth: depth,
                ),
              ]
            : const [],
      ),
    );
  }
}
