import 'package:flutter/material.dart';

/// Three staggered pulsing dots, used as a loading indicator anywhere the
/// app wants the splash-screen look (currently: SplashScreen and the
/// vault-switching overlay in HomeScreen).
class FlashingDots extends StatefulWidget {
  final Color color;

  const FlashingDots({super.key, this.color = Colors.white});

  @override
  State<FlashingDots> createState() => _FlashingDotsState();
}

class _FlashingDotsState extends State<FlashingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final List<Animation<double>> _dotOpacities;
  late final List<Animation<double>> _dotScales;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    _dotOpacities = List.generate(3, (i) {
      final start = i * 0.2;
      final peak = start + 0.2;
      final end = peak + 0.2;
      return TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 0.25, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
          weight: 30,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.25).chain(CurveTween(curve: Curves.easeIn)),
          weight: 30,
        ),
        TweenSequenceItem(tween: ConstantTween(0.25), weight: 40),
      ]).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start.clamp(0.0, 1.0), end.clamp(0.0, 1.0)),
        ),
      );
    });

    _dotScales = List.generate(3, (i) {
      final start = i * 0.2;
      final end = (start + 0.4).clamp(0.0, 1.0);
      return TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 0.7, end: 1.0).chain(CurveTween(curve: Curves.easeOut)),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.7).chain(CurveTween(curve: Curves.easeIn)),
          weight: 50,
        ),
      ]).animate(CurvedAnimation(parent: _controller, curve: Interval(start, end)));
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: Transform.scale(
                scale: _dotScales[i].value,
                child: Opacity(
                  opacity: _dotOpacities[i].value,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}