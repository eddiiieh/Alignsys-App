import 'package:flutter/material.dart';

/// Represents a single breadcrumb segment
class BreadcrumbSegment {
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;

  BreadcrumbSegment({
    required this.label,
    this.onTap,
    this.icon,
  });
}

/// A breadcrumb navigation bar that shows the navigation path.
/// Automatically scrolls to the active (last) segment when segments change.
class BreadcrumbBar extends StatefulWidget {
  final List<BreadcrumbSegment> segments;
  final Color backgroundColor;
  final Color textColor;
  final Color activeTextColor;
  final double fontSize;

  const BreadcrumbBar({
    super.key,
    required this.segments,
    this.backgroundColor = Colors.white,
    this.textColor = const Color(0xFF666666),
    this.activeTextColor = const Color(0xFF072F5F),
    this.fontSize = 13,
  });

  @override
  State<BreadcrumbBar> createState() => _BreadcrumbBarState();
}

class _BreadcrumbBarState extends State<BreadcrumbBar> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BreadcrumbBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Scroll to end whenever segments change (e.g. user navigated deeper)
    if (oldWidget.segments.length != widget.segments.length ||
        oldWidget.segments.lastOrNull?.label !=
            widget.segments.lastOrNull?.label) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
    // Wait for the new frame so the layout is complete before scrolling
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.segments.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _buildBreadcrumbItems(),
        ),
      ),
    );
  }

  List<Widget> _buildBreadcrumbItems() {
    final items = <Widget>[];
    final segments = widget.segments;

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;

      // Add icon if this is the first segment and has an icon
      if (i == 0 && segment.icon != null) {
        items.add(
          Icon(
            segment.icon,
            size: 16,
            color: isLast ? widget.activeTextColor : widget.textColor,
          ),
        );
        items.add(const SizedBox(width: 6));
      }

      // Add the breadcrumb segment
      items.add(
        InkWell(
          onTap: isLast ? null : segment.onTap,
          borderRadius: BorderRadius.circular(4),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(
              segment.label,
              style: TextStyle(
                fontSize: widget.fontSize,
                fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                color: isLast ? widget.activeTextColor : widget.textColor,
                decoration: (!isLast && segment.onTap != null)
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: widget.textColor.withOpacity(0.4),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );

      // Add separator if not the last item
      if (!isLast) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: Colors.grey.shade400,
            ),
          ),
        );
      }
    }

    return items;
  }
}