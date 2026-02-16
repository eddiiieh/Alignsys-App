import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';

class SplashScreen extends StatefulWidget {
  final Duration minDuration;
  final String? logoAssetPath;

  const SplashScreen({
    Key? key,
    this.minDuration = const Duration(seconds: 3), // ✅ Reduced from 5 to 3 seconds
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

    // Ensure minimum splash duration
    Future.wait([
      Future.delayed(widget.minDuration),
      _checkAutoLogin(),
    ]).then((_) {
      // Navigation handled in _checkAutoLogin
    });
  }

  Future<void> _checkAutoLogin() async {
    final mFilesService = Provider.of<MFilesService>(context, listen: false);

    try {
      print('🚀 Starting auto-login check...');
      
      // 1. Load tokens first
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

      // 2. Restore the selected vault from SharedPreferences
      await mFilesService.restoreSelectedVault();
      print('   Vault restored: ${mFilesService.selectedVault?.guid}');

      // 3. If no vault in SharedPreferences, fetch vaults and select first one
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

        // Select the first vault
        await mFilesService.saveSelectedVault(vaults.first);
        print('   Selected first vault: ${vaults.first.name}');
      }

      // 4. Fetch M-Files user ID
      print('   Fetching M-Files user ID...');
      await mFilesService.fetchMFilesUserId();
      print('   M-Files user ID: ${mFilesService.mfilesUserId}');

      // 5. Verify mfilesUserId was set
      if (mFilesService.mfilesUserId == null) {
        print('❌ Failed to resolve M-Files user ID');
        if (!mounted) return;
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      // 6. Load initial data
      print('   Loading object types...');
      await mFilesService.fetchObjectTypes();
      
      print('   Loading views...');
      await mFilesService.fetchAllViews();
      
      print('   Loading recent objects...');
      await mFilesService.fetchRecentObjects();

      print('✅ Auto-login successful - navigating to home');

      // 7. Navigate to home
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
        widget.logoAssetPath ?? 'assets/alignsysop.png',
        height: 58,
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
              const SizedBox(height: 32),
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  strokeWidth: 3.0,
                  strokeCap: StrokeCap.round,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}