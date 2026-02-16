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

/// A breadcrumb navigation bar that shows the navigation path
class BreadcrumbBar extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      // ✅ REDUCED VERTICAL PADDING: Changed from 12 to 8
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(
            color: Colors.grey.shade200,
            width: 1,
          ),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _buildBreadcrumbItems(),
        ),
      ),
    );
  }

  List<Widget> _buildBreadcrumbItems() {
    final items = <Widget>[];

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;

      // Add icon if this is the first segment and has an icon
      if (i == 0 && segment.icon != null) {
        items.add(
          Icon(
            segment.icon,
            size: 16,
            color: isLast ? activeTextColor : textColor,
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
                fontSize: fontSize,
                fontWeight: isLast ? FontWeight.w700 : FontWeight.w500,
                color: isLast ? activeTextColor : textColor,
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
            padding: const EdgeInsets.symmetric(horizontal: 6),
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