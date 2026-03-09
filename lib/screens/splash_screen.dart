import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';

class SplashScreen extends StatefulWidget {
  final Duration minDuration;
  final String? logoAssetPath;

  const SplashScreen({
    Key? key,
    this.minDuration = const Duration(seconds: 3),
    this.logoAssetPath,
  }) : super(key: key);

  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _scale = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    _opacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
    );

    _controller.forward();

    Future.wait([
      Future.delayed(widget.minDuration),
      _checkAutoLogin(),
    ]).then((_) {});
  }

  Future<void> _checkAutoLogin() async {
    final mFilesService = Provider.of<MFilesService>(context, listen: false);

    try {
      print('🚀 Starting auto-login check...');

      final hasTokens = await mFilesService.loadTokens();
      print('   Tokens loaded: $hasTokens');
      print('   AccessToken: ${mFilesService.accessToken != null ? "present" : "null"}');
      print('   UserId: ${mFilesService.userId}');

      if (!hasTokens) {
        print('   No tokens - navigating to login');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      await mFilesService.restoreSelectedVault();
      print('   Vault restored: ${mFilesService.selectedVault?.guid}');

      if (mFilesService.selectedVault == null) {
        print('   No saved vault, fetching available vaults...');
        final vaults = await mFilesService.getUserVaults();
        print('   Found ${vaults.length} vaults');

        if (vaults.isEmpty) {
          print('   No vaults available - navigating to login');
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/login');
          return;
        }

        await mFilesService.saveSelectedVault(vaults.first);
        print('   Selected first vault: ${vaults.first.name}');
      }

      print('   Fetching M-Files user ID...');
      await mFilesService.fetchMFilesUserId();
      print('   M-Files user ID: ${mFilesService.mfilesUserId}');

      if (mFilesService.mfilesUserId == null) {
        print('❌ Failed to resolve M-Files user ID');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      print('   Loading object types...');
      await mFilesService.fetchObjectTypes();

      print('   Loading views...');
      await mFilesService.fetchAllViews();

      print('   Loading recent objects...');
      await mFilesService.fetchRecentObjects();

      print('✅ Auto-login successful - navigating to home');

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      print('❌ Auto-login failed: $e');
      print('   Stack trace: ${StackTrace.current}');

      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildLogo() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.asset(
        widget.logoAssetPath ?? 'assets/alignsysnew.png',
        height: 70,
        fit: BoxFit.contain,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF072F5F),
      body: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) => Transform.scale(
                  scale: _scale.value,
                  child: Opacity(
                    opacity: _opacity.value,
                    child: child,
                  ),
                ),
                child: _buildLogo(),
              ),
              const SizedBox(height: 40),
              const _FlashingDots(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Flashing dots indicator ───────────────────────────────────────────────

class _FlashingDots extends StatefulWidget {
  const _FlashingDots();

  @override
  State<_FlashingDots> createState() => _FlashingDotsState();
}

class _FlashingDotsState extends State<_FlashingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  // Each dot pulses with a staggered delay via interval curves
  late final List<Animation<double>> _dotOpacities;
  late final List<Animation<double>> _dotScales;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();

    // Stagger: dot 0 starts at 0%, dot 1 at 20%, dot 2 at 40%
    // Each dot is "on" for ~40% of the cycle then fades
    _dotOpacities = List.generate(3, (i) {
      final start = i * 0.2;
      final peak = start + 0.2;
      final end = peak + 0.2;
      return TweenSequence<double>([
        TweenSequenceItem(
          tween: Tween(begin: 0.25, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 30,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.25)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 30,
        ),
        TweenSequenceItem(
          tween: ConstantTween(0.25),
          weight: 40,
        ),
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
          tween: Tween(begin: 0.7, end: 1.0)
              .chain(CurveTween(curve: Curves.easeOut)),
          weight: 50,
        ),
        TweenSequenceItem(
          tween: Tween(begin: 1.0, end: 0.7)
              .chain(CurveTween(curve: Curves.easeIn)),
          weight: 50,
        ),
      ]).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(start, end),
        ),
      );
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
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                    ),
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