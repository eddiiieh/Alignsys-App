import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mfiles_app/services/mfiles_service.dart';

/// Green = checked out by the current user, red = checked out by someone
/// else. Renders just [child] if the object isn't checked out.
class CheckoutBadge extends StatelessWidget {
  final bool isCheckedOut;
  final int? checkoutUserId;
  final Widget child;

  const CheckoutBadge({
    super.key,
    required this.isCheckedOut,
    required this.checkoutUserId,
    required this.child,
  });

  static const Color mineColor = Color(0xFF0F766E);
  static const Color othersColor = Color(0xFFDC2626);

  @override
  Widget build(BuildContext context) {
    if (!isCheckedOut) return child;
    final svc = context.watch<MFilesService>();
    final mine = checkoutUserId == null || checkoutUserId == svc.mfilesUserId;
    final color = mine ? mineColor : othersColor;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -4,
          bottom: -4,
          child: Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: const Icon(Icons.drive_file_rename_outline, size: 10, color: Colors.white),
          ),
        ),
      ],
    );
  }
}