import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

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

class BreadcrumbBar extends StatefulWidget {
  final List<BreadcrumbSegment> segments;

  /// Optional overrides. When null, the widget resolves these from
  /// `context.colors` so it flips automatically with the theme.
  final Color? backgroundColor;
  final Color? textColor;
  final Color? activeTextColor;
  final double fontSize;

  const BreadcrumbBar({
    super.key,
    required this.segments,
    this.backgroundColor,
    this.textColor,
    this.activeTextColor,
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
    if (oldWidget.segments.length != widget.segments.length ||
        oldWidget.segments.lastOrNull?.label !=
            widget.segments.lastOrNull?.label) {
      _scrollToEnd();
    }
  }

  void _scrollToEnd() {
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

    final c = context.colors;
    final bg = widget.backgroundColor ?? c.surfaceElevated;
    final textColor = widget.textColor ?? c.textSecondary;
    final activeColor = widget.activeTextColor ?? c.brand;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        border: Border(
          bottom: BorderSide(color: c.divider, width: 1),
        ),
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        scrollDirection: Axis.horizontal,
        child: Row(
          children: _buildBreadcrumbItems(c, textColor, activeColor),
        ),
      ),
    );
  }

  List<Widget> _buildBreadcrumbItems(
    AppColorsExtension c,
    Color textColor,
    Color activeColor,
  ) {
    final items = <Widget>[];
    final segments = widget.segments;

    for (int i = 0; i < segments.length; i++) {
      final segment = segments[i];
      final isLast = i == segments.length - 1;

      if (i == 0 && segment.icon != null) {
        items.add(
          Icon(
            segment.icon,
            size: 16,
            color: isLast ? activeColor : textColor,
          ),
        );
        items.add(const SizedBox(width: 6));
      }

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
                color: isLast ? activeColor : textColor,
                decoration: (!isLast && segment.onTap != null)
                    ? TextDecoration.underline
                    : TextDecoration.none,
                decorationColor: textColor.withOpacity(0.4),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      );

      if (!isLast) {
        items.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Icon(
              Icons.chevron_right_rounded,
              size: 16,
              color: c.textTertiary,
            ),
          ),
        );
      }
    }

    return items;
  }
}