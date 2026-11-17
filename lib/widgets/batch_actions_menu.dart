import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class BatchMenuAction {
  final String value;
  final IconData icon;
  final String label;

  const BatchMenuAction(this.value, this.icon, this.label);
}

class BatchActionsMenu extends StatelessWidget {
  const BatchActionsMenu({
    super.key,
    required this.onSelected,
    this.items = const [
      BatchMenuAction('history', Icons.history_rounded, 'Version History'),
      BatchMenuAction('copy', Icons.copy_rounded, 'Make a copy'),
      BatchMenuAction('download', Icons.download_rounded, 'Download'),
      BatchMenuAction('convertPdf', Icons.picture_as_pdf_rounded, 'Convert to PDF'),
    ],
    this.disabledValues = const <String>{},
    this.icon = Icons.more_vert,
    this.iconColor,
    this.tooltip = 'More',
  });

  final Set<String> disabledValues;
  final ValueChanged<String> onSelected;
  final List<BatchMenuAction> items;
  final IconData icon;
  final Color? iconColor;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = items.where((a) => !disabledValues.contains(a.value)).toList();

    return PopupMenuButton<String>(
      tooltip: tooltip,
      iconColor: iconColor,
      color: c.surfaceElevated,
      elevation: 6,
      shadowColor: c.shadow,
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: c.divider),
      ),
      constraints: const BoxConstraints(minWidth: 190),
      onSelected: onSelected,
      itemBuilder: (_) => visible
          .map((a) => _buildMenuItem(context, a.value, a.icon, a.label))
          .toList(),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    BuildContext context,
    String value,
    IconData icon,
    String label,
  ) {
    final c = context.colors;
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: c.brandTint,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: c.brand),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}