import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

class ScrollJumpFab extends StatefulWidget {
  final ScrollController controller;
  const ScrollJumpFab({super.key, required this.controller});
  @override
  State<ScrollJumpFab> createState() => _ScrollJumpFabState();
}

class _ScrollJumpFabState extends State<ScrollJumpFab> {
  bool _show = false, _up = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_update);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_update);
    super.dispose();
  }

  void _update() {
    if (!mounted || !widget.controller.hasClients) return;
    final p = widget.controller.position;
    final show = p.maxScrollExtent > 500;
    final up = p.pixels > p.maxScrollExtent / 2;
    if (show != _show || up != _up) setState(() { _show = show; _up = up; });
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) => _update());
    return AnimatedScale(
      scale: _show ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: FloatingActionButton.small(
        heroTag: null,
        elevation: 3,
        backgroundColor: Colors.white,
        foregroundColor: AppColors.primary,
        onPressed: () {
          final p = widget.controller.position;
          widget.controller.animateTo(_up ? 0 : p.maxScrollExtent,
              duration: const Duration(milliseconds: 350), curve: Curves.easeOutCubic);
        },
        child: Icon(_up ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded),
      ),
    );
  }
}