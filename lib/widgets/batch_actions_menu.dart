import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// Reusable action label + icon for [BatchActionsMenu].
class BatchMenuAction {
  final String value;
  final IconData icon;
  final String label;

  const BatchMenuAction(this.value, this.icon, this.label);
}

/// Shared "More" popup menu for batch/multi-select action bars.
/// Consistent rounded-card style, icon+label rows, and shadow —
/// used by HomeScreen, ViewDetailsScreen, and ViewItemsScreen.
class BatchActionsMenu extends StatelessWidget {
  const BatchActionsMenu({
    super.key,
    required this.onSelected,
    this.items = const [
      BatchMenuAction('history', Icons.history_rounded, 'Version History'),
      BatchMenuAction('download', Icons.download_rounded, 'Download'),
      BatchMenuAction(
        'convertPdf',
        Icons.picture_as_pdf_rounded,
        'Convert to PDF',
      ),
    ],
  });

  final ValueChanged<String> onSelected;
  final List<BatchMenuAction> items;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'More',
      color: Colors.white,
      elevation: 6,
      shadowColor: Colors.black.withOpacity(0.18),
      offset: const Offset(0, 44),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.shade100),
      ),
      constraints: const BoxConstraints(minWidth: 190),
      onSelected: onSelected,
      itemBuilder:
          (_) => items
              .map((a) => _buildMenuItem(a.value, a.icon, a.label))
              .toList(),
    );
  }

  PopupMenuItem<String> _buildMenuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 46,
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 16, color: AppColors.primary),
          ),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1A1A1A),
            ),
          ),
        ],
      ),
    );
  }
}