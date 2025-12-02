import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SplashScreen extends StatefulWidget {
  final Duration minDuration;
  final String? logoAssetPath;

  const SplashScreen({
    Key? key,
    this.minDuration = const Duration(seconds: 2),
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
    ]);
  }

  Future<void> _checkAutoLogin() async {
    final mFilesService = Provider.of<MFilesService>(context, listen: false);

    try {
      final hasTokens = await mFilesService.loadTokens();

      if (hasTokens) {
        final vaults = await mFilesService.getUserVaults();

        if (vaults.isNotEmpty) {
          final prefs = await SharedPreferences.getInstance();
          final selectedVaultGuid = prefs.getString('selected_vault_guid');

          mFilesService.selectedVault = vaults.firstWhere(
            (v) => v.guid == selectedVaultGuid,
            orElse: () => vaults.first,
          );

          if (!mounted) return;
          Navigator.pushReplacementNamed(context, '/home');
          return;
        }
      }
    } catch (e) {
      print("Auto-login failed: $e");
      // fallback to login
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Widget _buildLogo() {
    return Image.asset(
      widget.logoAssetPath ?? 'assets/alignsyslogo.png',
      width: 120,
      height: 120,
      fit: BoxFit.contain,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              theme.primaryColor,
              theme.primaryColorDark,
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
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
                const SizedBox(height: 20),
                const SizedBox(
                  width: 36,
                  height: 36,
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                    strokeWidth: 2.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
