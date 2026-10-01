import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class PickerGroup<T> {
  final String? title; // null = no header, always open
  final IconData icon;
  final List<T> items;
  final bool initiallyOpen;
  const PickerGroup({
    this.title,
    this.icon = Icons.folder_outlined,
    required this.items,
    this.initiallyOpen = false,
  });
}

Future<T?> showGroupedPickerSheet<T>(
  BuildContext context, {
  required String title,
  required IconData headerIcon,
  required List<PickerGroup<T>> groups,
  required String Function(T) labelOf,
  String? Function(T)? subtitleOf,
  T? selected,
  bool Function(T a, T b)? isSame,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _GroupedPickerSheet<T>(
      title: title,
      headerIcon: headerIcon,
      groups: groups,
      labelOf: labelOf,
      subtitleOf: subtitleOf,
      selected: selected,
      isSame: isSame,
    ),
  );
}

class _GroupedPickerSheet<T> extends StatefulWidget {
  final String title;
  final IconData headerIcon;
  final List<PickerGroup<T>> groups;
  final String Function(T) labelOf;
  final String? Function(T)? subtitleOf;
  final T? selected;
  final bool Function(T, T)? isSame;

  const _GroupedPickerSheet({
    required this.title,
    required this.headerIcon,
    required this.groups,
    required this.labelOf,
    this.subtitleOf,
    this.selected,
    this.isSame,
  });

  @override
  State<_GroupedPickerSheet<T>> createState() => _GroupedPickerSheetState<T>();
}

class _GroupedPickerSheetState<T> extends State<_GroupedPickerSheet<T>> {
  final _q = TextEditingController();
  final Set<int> _open = {};

  bool _same(T a, T b) => widget.isSame?.call(a, b) ?? a == b;
  bool _isSel(T x) => widget.selected != null && _same(x, widget.selected as T);

  @override
  void initState() {
    super.initState();
    final total = widget.groups.fold<int>(0, (n, g) => n + g.items.length);
    for (var i = 0; i < widget.groups.length; i++) {
      final g = widget.groups[i];
      if (g.initiallyOpen ||
          g.title == null ||
          total <= 8 ||
          g.items.any(_isSel)) {
        _open.add(i);
      }
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final query = _q.text.trim().toLowerCase();
    final searching = query.isNotEmpty;
    final total = widget.groups.fold<int>(0, (n, g) => n + g.items.length);

    final sections = <Widget>[];
    var shown = 0;
    for (var i = 0; i < widget.groups.length; i++) {
      final g = widget.groups[i];
      final items =
          searching
              ? g.items
                  .where(
                    (x) => widget.labelOf(x).toLowerCase().contains(query),
                  )
                  .toList()
              : g.items;
      if (items.isEmpty) continue;
      shown += items.length;
      sections.add(
        _section(
          i,
          g,
          items,
          searching || g.title == null || _open.contains(i),
          searching,
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 14),
                _header(total),
                _searchField(),
                Flexible(
                  child:
                      shown == 0
                          ? _empty()
                          : ListView(
                            shrinkWrap: true,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
                            children: sections,
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _header(int total) => Container(
    width: double.infinity,
    margin: const EdgeInsets.symmetric(horizontal: 16),
    padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
    decoration: BoxDecoration(
      color: AppColors.primary,
      borderRadius: BorderRadius.circular(14),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(widget.headerIcon, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '$total option${total == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.close, color: Colors.white70),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    ),
  );

  Widget _searchField() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
    child: TextField(
      controller: _q,
      onChanged: (_) => setState(() {}),
      decoration: InputDecoration(
        hintText: 'Search...',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
        prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
        suffixIcon:
            _q.text.isEmpty
                ? null
                : IconButton(
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: Colors.grey.shade400,
                  ),
                  onPressed: () => setState(_q.clear),
                ),
        filled: true,
        fillColor: AppColors.surfaceLight,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    ),
  );

  Widget _empty() => Padding(
    padding: const EdgeInsets.all(32),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.search_off, size: 36, color: Colors.grey.shade300),
        const SizedBox(height: 8),
        Text(
          'No matches found',
          style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
        ),
      ],
    ),
  );

  // ── Section: ORIGINAL header / count pill / chevron ──────────────────
  Widget _section(
    int index,
    PickerGroup<T> g,
    List<T> items,
    bool open,
    bool searching,
  ) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (g.title != null)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap:
                  searching
                      ? null
                      : () => setState(
                        () => _open.contains(index)
                            ? _open.remove(index)
                            : _open.add(index),
                      ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 4,
                ),
                child: Row(
                  children: [
                    Icon(g.icon, size: 16, color: AppColors.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        g.title!.toUpperCase(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${items.length}',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    if (!searching) ...[
                      const SizedBox(width: 6),
                      AnimatedRotation(
                        turns: open ? 0.5 : 0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 20,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child:
                open
                    ? Container(
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          for (var i = 0; i < items.length; i++) ...[
                            _row(items[i]),
                            if (i != items.length - 1)
                              // Slimmer divider: hairline + subtle tint
                              Divider(
                                height: 1,
                                thickness: 0.5,
                                indent: 16,
                                color: Colors.black.withOpacity(0.06),
                              ),
                          ],
                        ],
                      ),
                    )
                    : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  // ── Row: slimmer vertical padding only (was 14, now 11) ──────────────
  Widget _row(T item) {
    final sel = _isSel(item);
    final sub = widget.subtitleOf?.call(item);
    return InkWell(
      onTap: () => Navigator.pop(context, item),
      child: Container(
        color: sel ? const Color(0xFFEFF6FF) : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.labelOf(item),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.3,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      color:
                          sel ? AppColors.primary : const Color(0xFF1E293B),
                    ),
                  ),
                  if (sub != null && sub.isNotEmpty) ...[
                    const SizedBox(height: 3),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 10),
            sel
                ? const Icon(
                  Icons.check_rounded,
                  size: 20,
                  color: AppColors.primary,
                )
                : const SizedBox(width: 20),
          ],
        ),
      ),
    );
  }
}