import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../widgets/network_banner.dart';
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
    if (msg.contains('401') || msg.contains('unauthorized')) {
      return 'Invalid username or password.';
    }
    if (msg.contains('socketexception') ||
        msg.contains('failed host lookup') ||
        msg.contains('network')) {
      return 'Network error. Check your connection and try again.';
    }
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

      // Tell the OS to save these credentials to Google Password Manager / Keychain
      TextInput.finishAutofillContext(shouldSave: true);

      final vaults = await mFilesService.getUserVaults();
      if (vaults.isEmpty) throw Exception('No vaults available for this user.');

      setState(() {
        _vaults = vaults;
        _selectedVault = vaults.first;
      });
      _animController.forward();
    } catch (e) {
      // Don't save credentials if login failed
      TextInput.finishAutofillContext(shouldSave: false);
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

  /// Shows the forgot-password bottom sheet modal.
  void _showForgotPasswordSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ForgotPasswordSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _primaryBlue,
      body: NetworkBanner(
        child: Center(
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
                      height: 85,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
                const SizedBox(height: 22),

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
                              child: AutofillGroup(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    _buildTextField(
                                      controller: _usernameController,
                                      label: 'Email / Username',
                                      icon: Icons.person_outline,
                                      keyboardType: TextInputType.emailAddress,
                                      errorText: _usernameError,
                                      autofillHints: const [
                                        AutofillHints.username,
                                        AutofillHints.email,
                                      ],
                                    ),
                                    const SizedBox(height: 16),
                                    _buildTextField(
                                      controller: _passwordController,
                                      label: 'Password',
                                      icon: Icons.lock_outline,
                                      obscureText: !_showPassword,
                                      autofillHints: const [AutofillHints.password],
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
                                    const SizedBox(height: 12),

                                    // ── FORGOT PASSWORD LINK ──
                                    Align(
                                      alignment: Alignment.centerRight,
                                      child: TextButton(
                                        onPressed: _showForgotPasswordSheet,
                                        style: TextButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                              vertical: 4, horizontal: 0),
                                          minimumSize: Size.zero,
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        child: Text(
                                          'Forgot password?',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color: _accentBlue.withOpacity(0.85),
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),

                                    const SizedBox(height: 12),
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
                                'Choose your repository',
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
                                          'Select Repository',
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
                                              'Proceed to repository',
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
    )
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
    List<String>? autofillHints,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      autofillHints: autofillHints,
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

// ---------------------------------------------------------------------------
// Forgot Password Bottom Sheet
// ---------------------------------------------------------------------------

/// Isolated widget so it carries its own state and doesn't rebuild the parent.
class _ForgotPasswordSheet extends StatefulWidget {
  const _ForgotPasswordSheet();

  @override
  State<_ForgotPasswordSheet> createState() => _ForgotPasswordSheetState();
}

enum _ResetState { idle, loading, success, error }

class _ForgotPasswordSheetState extends State<_ForgotPasswordSheet> {
  final _emailController = TextEditingController();
  _ResetState _state = _ResetState.idle;
  String? _emailError;
  String _errorMessage = '';

  static const _primaryBlue = Color(0xFF072F5F);
  static const _accentBlue = Color.fromRGBO(25, 76, 129, 1);

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) {
    return RegExp(r'^[\w\-.]+@([\w\-]+\.)+[\w\-]{2,}$').hasMatch(email);
  }

  Future<void> _submit() async {
    final email = _emailController.text.trim();

    setState(() {
      _emailError = email.isEmpty
          ? 'Please enter your email address.'
          : !_isValidEmail(email)
              ? 'Please enter a valid email address.'
              : null;
    });

    if (_emailError != null) return;

    setState(() => _state = _ResetState.loading);

    try {
      await context.read<MFilesService>().requestPasswordReset(email);
      if (mounted) setState(() => _state = _ResetState.success);
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _ResetState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(24, 24, 24, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Handle bar
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Icon + title
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _primaryBlue.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock_reset, color: _accentBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Reset your password',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: _primaryBlue,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    "We'll email you a reset link.",
                    style: TextStyle(fontSize: 13, color: Colors.grey),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── SUCCESS STATE ──
          if (_state == _ResetState.success) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline,
                      color: Colors.green.shade600, size: 22),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Check your inbox! If an account exists for ${_emailController.text.trim()}, you\'ll receive a reset link shortly.',
                      style: TextStyle(
                          color: Colors.green.shade800, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Done',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
            ),
          ]

          // ── IDLE / LOADING / ERROR STATE ──
          else ...[
            TextField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Email address',
                prefixIcon:
                    const Icon(Icons.email_outlined, color: _accentBlue),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12)),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _accentBlue, width: 2),
                ),
                errorText: _emailError,
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),

            // Inline error banner (API-level errors)
            if (_state == _ResetState.error) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade600, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage,
                        style: TextStyle(
                            color: Colors.red.shade700, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _state == _ResetState.loading ? null : _submit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primaryBlue,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                disabledBackgroundColor: Colors.grey.shade300,
                elevation: 2,
              ),
              child: _state == _ResetState.loading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.5,
                        valueColor:
                            AlwaysStoppedAnimation<Color>(_accentBlue),
                      ),
                    )
                  : const Text(
                      'Send Reset Link',
                      style: TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(color: Colors.grey)),
            ),
          ],
        ],
      ),
    );
  }
}