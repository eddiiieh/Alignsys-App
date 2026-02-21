import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/mfiles_service.dart';
import '../models/vault.dart';

class LoginVaultScreen extends StatefulWidget {
  const LoginVaultScreen({super.key});

  @override
  State<LoginVaultScreen> createState() => _LoginVaultScreenState();
}

class _LoginVaultScreenState extends State<LoginVaultScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _loading = false;
  bool _proceedLoading = false;
  bool _showPassword = false;
  List<Vault> _vaults = [];
  Vault? _selectedVault;

  String? _usernameError;

  late final AnimationController _animController;
  late final Animation<Offset> _loginSlide;
  late final Animation<Offset> _vaultSlide;
  late final Animation<double> _vaultFade;

  static const _primaryBlue = Color(0xFF072F5F);
  static const _accentBlue = Color.fromRGBO(25, 76, 129, 1);

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );

    _loginSlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-1.5, 0),
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));

    _vaultSlide = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));

    _vaultFade = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _animController, curve: const Interval(0.4, 1.0)),
    );
  }

  @override
  void dispose() {
    _animController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String _friendlyLoginError(Object e) {
    final msg = e.toString().toLowerCase();

    // If your service throws "Exception: login failed 401"
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'Invalid username or password.';
    }

    // Common network cases
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network')) {
      return 'Network error. Check your connection and try again.';
    }

    // Fallback
    return 'Login failed. Please try again.';
  }

  Future<void> _logout() async {
    final s = context.read<MFilesService>();
    await s.logout();

    if (!mounted) return;
    await _animController.reverse();
    setState(() {
      _vaults = [];
      _selectedVault = null;
      _passwordController.clear();
      _loading = false;
      _proceedLoading = false;
    });
  }

  void _login() async {
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final mFilesService = context.read<MFilesService>();

    setState(() {
      _usernameError = username.isEmpty ? 'This field is required' : null;
    });
    if (_usernameError != null) return;

    setState(() => _loading = true);

    try {
      final success = await mFilesService.login(username, password);
      if (!success) throw Exception('Login failed. Check credentials.');

      final vaults = await mFilesService.getUserVaults();
      if (vaults.isEmpty) throw Exception('No vaults available for this user.');

      setState(() {
        _vaults = vaults;
        _selectedVault = vaults.first;
      });
      // Trigger the slide animation
      _animController.forward();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyLoginError(e)),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          duration: const Duration(seconds: 4),
        ),
      );
    }
    setState(() => _loading = false);
  }

  void _proceedToVault() async {
    if (_selectedVault == null) return;

    final mFilesService = context.read<MFilesService>();
    mFilesService.selectedVault = _selectedVault!;

    setState(() => _proceedLoading = true);

    try {
      await mFilesService.fetchMFilesUserId();
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error setting up vault: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _proceedLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryBlue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Logo Section
                Container(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.asset(
                      'assets/alignsysnew.png',
                      height: 140,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // Animated area: login form slides out, vault picker slides in
                ClipRect(
                  child: Stack(
                    children: [
                      // ── LOGIN FORM ──
                      SlideTransition(
                        position: _loginSlide,
                        child: Column(
                          children: [
                            const Text(
                              'Welcome back',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildCard(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildTextField(
                                    controller: _usernameController,
                                    label: 'Email / Username',
                                    icon: Icons.person_outline,
                                    keyboardType: TextInputType.emailAddress,
                                    errorText: _usernameError,
                                  ),
                                  const SizedBox(height: 16),
                                  _buildTextField(
                                    controller: _passwordController,
                                    label: 'Password',
                                    icon: Icons.lock_outline,
                                    obscureText: !_showPassword,
                                    suffixIcon: IconButton(
                                      icon: Icon(
                                        _showPassword
                                            ? Icons.visibility
                                            : Icons.visibility_off,
                                        color: Colors.grey.shade600,
                                      ),
                                      onPressed: () => setState(
                                          () => _showPassword = !_showPassword),
                                    ),
                                  ),
                                  const SizedBox(height: 20),
                                  _loading
                                      ? const Center(
                                          child: CircularProgressIndicator(
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                    _accentBlue),
                                          ),
                                        )
                                      : ElevatedButton(
                                          onPressed: _login,
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: _primaryBlue,
                                            foregroundColor: Colors.white,
                                            padding: const EdgeInsets.symmetric(
                                                vertical: 16),
                                            shape: RoundedRectangleBorder(
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            elevation: 2,
                                          ),
                                          child: const Text(
                                            'Login',
                                            style: TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),

                      // ── VAULT PICKER ──
                      SlideTransition(
                        position: _vaultSlide,
                        child: FadeTransition(
                          opacity: _vaultFade,
                          child: Column(
                            children: [
                              const Text(
                                'Choose your vault',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 12),
                              _buildCard(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.all(8),
                                          decoration: BoxDecoration(
                                            color: _primaryBlue.withOpacity(0.1),
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: const Icon(Icons.storage,
                                              color: _accentBlue, size: 20),
                                        ),
                                        const SizedBox(width: 12),
                                        const Text(
                                          'Select Vault',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.bold,
                                            color: _accentBlue,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    DropdownButtonFormField<Vault>(
                                      value: _selectedVault,
                                      items: _vaults
                                          .map((v) => DropdownMenuItem(
                                                value: v,
                                                child: Row(
                                                  children: [
                                                    const Icon(Icons.folder,
                                                        size: 18,
                                                        color: _accentBlue),
                                                    const SizedBox(width: 8),
                                                    Text(v.name),
                                                  ],
                                                ),
                                              ))
                                          .toList(),
                                      onChanged: (v) =>
                                          setState(() => _selectedVault = v),
                                      decoration: InputDecoration(
                                        border: OutlineInputBorder(
                                            borderRadius:
                                                BorderRadius.circular(12)),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: BorderSide(
                                              color: Colors.grey.shade300),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          borderSide: const BorderSide(
                                              color: _accentBlue, width: 2),
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                                horizontal: 16, vertical: 12),
                                        filled: true,
                                        fillColor: Colors.grey.shade50,
                                      ),
                                      icon: const Icon(Icons.arrow_drop_down,
                                          color: _accentBlue),
                                    ),
                                    const SizedBox(height: 16),
                                    ElevatedButton(
                                      onPressed: (_selectedVault == null ||
                                              _proceedLoading)
                                          ? null
                                          : _proceedToVault,
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: _primaryBlue,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 16),
                                        shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                        ),
                                        elevation: 2,
                                        disabledBackgroundColor:
                                            Colors.grey.shade300,
                                      ),
                                      child: _proceedLoading
                                          ? const SizedBox(
                                              height: 20,
                                              width: 20,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                valueColor:
                                                    AlwaysStoppedAnimation<
                                                        Color>(_accentBlue),
                                              ),
                                            )
                                          : const Text(
                                              'Proceed to Vault',
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                    ),
                                    const SizedBox(height: 12),
                                    TextButton.icon(
                                      onPressed: _logout,
                                      icon: const Icon(Icons.arrow_back,
                                          size: 16, color: Colors.grey),
                                      label: const Text(
                                        'Back to login',
                                        style: TextStyle(color: Colors.grey),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.15),
            blurRadius: 20,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool obscureText = false,
    String? errorText,
    Widget? suffixIcon,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color.fromRGBO(25, 76, 129, 1)),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(
              color: Color.fromRGBO(25, 76, 129, 1), width: 2),
        ),
        errorText: errorText,
        filled: true,
        fillColor: Colors.grey.shade50,
        suffixIcon: suffixIcon,
      ),
    );
  }
}