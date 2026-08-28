import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../theme/app_colors.dart';
import '../widgets/flashing_dots.dart';

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

      await mFilesService.loadServerAddress();
      print('   Server address: ${mFilesService.serverAddress ?? "(none saved)"}');

      final hasTokens = await mFilesService.loadTokens();
      print('   Tokens loaded: $hasTokens');
      print('   AccessToken: ${mFilesService.accessToken != null ? "present" : "null"}');
      print('   UserId: ${mFilesService.userId}');

      if (!mFilesService.hasServerAddress) {
        if (hasTokens) {
          // Existing user from before this feature shipped — they have valid
          // tokens but never entered a server address. Default them silently
          // to the Alignsys cloud host rather than surprising them with a
          // new screen; only fresh installs with no tokens see it.
          print('   Existing user with no server address - defaulting silently to cloud host');
          await mFilesService.setServerAddress('alignsys.tech');
        } else {
          print('   Fresh install, no server address - navigating to server address screen');
          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/server_address');
          return;
        }
      }

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
      backgroundColor: AppColors.primary,
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
              const FlashingDots(),
            ],
          ),
        ),
      ),
    );
  }
}