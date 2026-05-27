// lib/dss/screens/dss_upload_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/mfiles_service.dart';
import '../../theme/app_colors.dart';
import '../services/dss_auth_service.dart';
import '../services/dss_api_service.dart';

// ── Entry point ──────────────────────────────────────────────────────────────

class DssUploadScreen extends StatefulWidget {
  const DssUploadScreen({super.key});

  @override
  State<DssUploadScreen> createState() => _DssUploadScreenState();
}

class _DssUploadScreenState extends State<DssUploadScreen> {
  PlatformFile? _picked;
  bool          _busy  = false;
  String?       _error;

  static const int          _maxBytes          = 20 * 1024 * 1024;
  static const List<String> _allowedExtensions = [
    'pdf', 'doc', 'docx', 'xls', 'xlsx',
    'ppt', 'pptx', 'csv', 'rtf',
    'png', 'jpg', 'jpeg',
  ];

  late DssApiService  _api;
  late DssAuthService _auth;

  @override
  void initState() {
    super.initState();
    final mfiles = context.read<MFilesService>();
    _auth = DssAuthService()
      ..accessToken  = mfiles.dssAccessToken
      ..refreshToken = mfiles.dssRefreshToken;

    // Restore userInfo from the stored DSS JWT so we can read the email
    if (mfiles.dssAccessToken != null) {
      final payload = _auth.decodePayload(mfiles.dssAccessToken!);
      if (payload != null) {
        _auth.userInfo = DssUserInfo.fromJwtPayload(payload);
      }
    }
    _api = DssApiService(authService: _auth);
  }

  // ── File picker ───────────────────────────────────────────────────────────

  Future<void> _pickFile() async {
    setState(() => _error = null);

    final result = await FilePicker.pickFiles(
      type:              FileType.custom,
      allowedExtensions: _allowedExtensions,
      withData:          false,
      withReadStream:    false,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;
    if (file.size > _maxBytes) {
      setState(() => _error = 'File exceeds the 20 MB limit.');
      return;
    }

    setState(() => _picked = file);
    if (!mounted) return;
    _showActionSheet(file);
  }

  // ── Action sheet ──────────────────────────────────────────────────────────

  void _showActionSheet(PlatformFile file) {
    showModalBottomSheet(
      context:          context,
      backgroundColor:  Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ActionSheet(
        file:       file,
        onSignNow:  () { Navigator.pop(context); _handleSignNow(file); },
        onSendTo:   () { Navigator.pop(context); _handleSendToOthers(file); },
        onSaveLater:() { Navigator.pop(context); _handleSaveLater(file); },
        onCancel:   () { Navigator.pop(context); setState(() => _picked = null); },
      ),
    );
  }

  // ── Action: Sign Now ──────────────────────────────────────────────────────
  // Posts the file with signerEmail = current user's DSS email,
  // then opens the returned URL in a WebView immediately.

  Future<void> _handleSignNow(PlatformFile file) async {
    final dssEmail = _auth.userInfo?.email ?? '';
    if (dssEmail.isEmpty) {
      _showError('Could not determine your DSS email. Please log out and back in.');
      return;
    }

    final result = await _post(
      file:        file,
      signerEmail: dssEmail,
      label:       'Preparing signing session…',
    );
    if (result == null) return;

    final url = result.url;
    if (!mounted) return;

    if (url != null && url.isNotEmpty) {
      _openWebView(url: url, title: 'Sign: ${file.name}');
    } else {
      // URL not returned yet — show success and let user find it in the dashboard
      _showSnack('Document registered in DSS. Open your Inbox to sign.');
    }
    setState(() => _picked = null);
  }

  // ── Action: Send to Others ────────────────────────────────────────────────
  // Shows a signer-collection dialog, posts the file with the signer list,
  // then opens the WebView only if the current user is among the signers.

  Future<void> _handleSendToOthers(PlatformFile file) async {
    final signers = await _showSignerDialog();
    if (signers == null || signers.isEmpty) return; // user cancelled

    // Build comma-separated email string for the API
    final signerEmail = signers.map((s) => s.email).join(',');

    final result = await _post(
      file:        file,
      signerEmail: signerEmail,
      label:       'Sending to signers…',
    );
    if (result == null) return;

    if (!mounted) return;

    final dssEmail = (_auth.userInfo?.email ?? '').toLowerCase().trim();
    final isSelf   = signers.any(
      (s) => s.email.toLowerCase().trim() == dssEmail,
    );

    if (isSelf && result.url != null && result.url!.isNotEmpty) {
      _openWebView(url: result.url!, title: 'Sign: ${file.name}');
    } else {
      final count = signers.length;
      _showSnack('Sent to $count signer${count == 1 ? '' : 's'} successfully.');
    }
    setState(() => _picked = null);
  }

  // ── Action: Save for Later ────────────────────────────────────────────────
  // Posts the file with an empty signerEmail (or the user's own email as
  // placeholder — update once Alignsys confirms the "save" contract).

  Future<void> _handleSaveLater(PlatformFile file) async {
    final dssEmail = _auth.userInfo?.email ?? '';

    final result = await _post(
      file:        file,
      signerEmail: dssEmail, // placeholder — confirm with Alignsys
      label:       'Saving…',
    );
    if (result == null) return;
    if (!mounted) return;

    _showSnack('Document saved to DSS for later.');
    setState(() => _picked = null);
  }

  // ── Shared post helper ────────────────────────────────────────────────────

  /// Shows a loading overlay, calls [postObjectFile], hides the overlay.
  /// Returns null on failure (error is shown inline).
  ///
  /// Note: DssUploadScreen does NOT have EDMS object metadata (objectId,
  /// classId, fileId, versionId, vaultGuid) because the user is picking a
  /// local file, not an EDMS document. Until Alignsys provides a standalone
  /// file-upload endpoint, we send placeholder zeros and the actual file
  /// path in signerEmail so the call at least exercises the auth flow.
  ///
  /// TODO: replace with correct endpoint once Alignsys confirms it.
  Future<DssPostResult?> _post({
    required PlatformFile file,
    required String       signerEmail,
    required String       label,
  }) async {
    setState(() { _busy = true; _error = null; });
    try {
      final mfiles = context.read<MFilesService>();
      final result = await _api.postObjectFile(
        objectId:    0,
        classId:     0,
        fileId:      0,
        versionId:   0,
        vaultGuid:   mfiles.vaultGuidWithBraces,
        signerEmail: signerEmail,
        dssUserId:   mfiles.dssUserId ?? 0,
      );

      if (!mounted) return null;

      if (!result.success) {
        setState(() => _error = result.message ?? 'Something went wrong.');
        return null;
      }
      return result;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // ── Signer dialog ─────────────────────────────────────────────────────────

  Future<List<DssSigner>?> _showSignerDialog() {
    return showDialog<List<DssSigner>>(
      context: context,
      builder: (_) => const _SignerDialog(),
    );
  }

  // ── WebView push ──────────────────────────────────────────────────────────

  void _openWebView({required String url, required String title}) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _DssWebViewScreen(
          url:          url,
          title:        title,
          accessToken:  _auth.accessToken  ?? '',
          refreshToken: _auth.refreshToken ?? '',
        ),
      ),
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:         Text(msg),
      backgroundColor: isError ? Colors.red.shade600 : Colors.green.shade600,
      behavior:        SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showError(String msg) => setState(() => _error = msg);

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Upload Document'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── Drop zone ──────────────────────────────────────────────
              GestureDetector(
                onTap: _busy ? null : _pickFile,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width:   double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  decoration: BoxDecoration(
                    color:        Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: _picked != null
                          ? AppColors.primary
                          : Colors.grey.shade300,
                      width: _picked != null ? 2 : 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color:      Colors.black.withOpacity(0.04),
                        blurRadius: 12,
                        offset:     const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding:    const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.08),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.upload_file_outlined,
                            size: 40, color: AppColors.primary),
                      ),
                      const SizedBox(height: 16),
                      const Text('Tap to pick a file',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'PDF, Word, Excel, PPT, CSV, Image, RTF\nMax 20 MB',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                ),
              ),
              // ── Loading indicator ──────────────────────────────────────
              if (_busy) ...[
                const SizedBox(height: 24),
                const CircularProgressIndicator(),
                const SizedBox(height: 8),
                Text('Processing…',
                    style: TextStyle(color: Colors.grey.shade600)),
              ],
              // ── Error banner ───────────────────────────────────────────
              if (_error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding:    const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color:        Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border:       Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(children: [
                    Icon(Icons.error_outline,
                        color: Colors.red.shade600, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_error!,
                          style: TextStyle(
                              color: Colors.red.shade700, fontSize: 13)),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Action sheet widget ───────────────────────────────────────────────────────

class _ActionSheet extends StatelessWidget {
  final PlatformFile  file;
  final VoidCallback  onSignNow;
  final VoidCallback  onSendTo;
  final VoidCallback  onSaveLater;
  final VoidCallback  onCancel;

  const _ActionSheet({
    required this.file,
    required this.onSignNow,
    required this.onSendTo,
    required this.onSaveLater,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          // File info
          Row(children: [
            const Icon(Icons.insert_drive_file_outlined,
                size: 20, color: AppColors.primary),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ]),
          const SizedBox(height: 4),
          Text(
            '${(file.size / 1024).toStringAsFixed(1)} KB  •  '
            '${file.extension?.toUpperCase() ?? 'FILE'}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
          ),
          const SizedBox(height: 20),
          // Actions
          _Action(
            icon:  Icons.draw_outlined,
            label: 'Sign Now',
            sub:   'Add your signature immediately',
            onTap: onSignNow,
          ),
          const SizedBox(height: 10),
          _Action(
            icon:  Icons.group_outlined,
            label: 'Send to Others',
            sub:   'Request signatures from specific people',
            onTap: onSendTo,
          ),
          const SizedBox(height: 10),
          _Action(
            icon:  Icons.bookmark_border_outlined,
            label: 'Save for Later',
            sub:   'Store in DSS without sending',
            onTap: onSaveLater,
          ),
          const SizedBox(height: 10),
          _Action(
            icon:  Icons.close,
            label: 'Cancel',
            sub:   'Discard selection',
            color: Colors.red.shade400,
            onTap: onCancel,
          ),
        ],
      ),
    );
  }
}

class _Action extends StatelessWidget {
  final IconData     icon;
  final String       label;
  final String       sub;
  final VoidCallback onTap;
  final Color?       color;

  const _Action({
    required this.icon,
    required this.label,
    required this.sub,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.primary;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap:        onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding:    const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color:        c.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border:       Border.all(color: c.withOpacity(0.15)),
          ),
          child: Row(children: [
            Container(
              padding:    const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: c.withOpacity(0.12), shape: BoxShape.circle),
              child: Icon(icon, size: 18, color: c),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: c)),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade600)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: c.withOpacity(0.5)),
          ]),
        ),
      ),
    );
  }
}

// ── Signer dialog ─────────────────────────────────────────────────────────────

class _SignerDialog extends StatefulWidget {
  const _SignerDialog();

  @override
  State<_SignerDialog> createState() => _SignerDialogState();
}

class _SignerDialogState extends State<_SignerDialog> {
  final _emailCtrl = TextEditingController();
  final _nameCtrl  = TextEditingController();
  final _signers   = <DssSigner>[];
  String? _inputError;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _nameCtrl.dispose();
    super.dispose();
  }

  bool _isValidEmail(String email) =>
      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email);

  void _addSigner() {
    final email = _emailCtrl.text.trim().toLowerCase();
    final name  = _nameCtrl.text.trim();

    if (email.isEmpty) {
      setState(() => _inputError = 'Email is required.');
      return;
    }
    if (!_isValidEmail(email)) {
      setState(() => _inputError = 'Enter a valid email address.');
      return;
    }
    if (_signers.any((s) => s.email == email)) {
      setState(() => _inputError = 'This email is already added.');
      return;
    }

    setState(() {
      _inputError = null;
      _signers.add(DssSigner(
        email: email,
        name:  name,
        order: _signers.length + 1,
      ));
      _emailCtrl.clear();
      _nameCtrl.clear();
    });
  }

  void _removeSigner(DssSigner s) {
    setState(() {
      _signers.removeWhere((x) => x.email == s.email);
      // Reorder
      for (var i = 0; i < _signers.length; i++) {
        _signers[i] = DssSigner(
          email: _signers[i].email,
          name:  _signers[i].name,
          order: i + 1,
        );
      }
    });
  }

  InputDecoration _inputDec(String hint) => InputDecoration(
        hintText:  hint,
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        filled:    true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:   BorderSide(color: Colors.grey.shade200)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:   BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:
                const BorderSide(color: AppColors.primary, width: 1.5)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide:   BorderSide(color: Colors.red.shade400)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:           RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      contentPadding:  const EdgeInsets.fromLTRB(20, 20, 20, 0),
      actionsPadding:  const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: const Text('Send to Others',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize:      MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Input row
              TextField(
                controller:  _nameCtrl,
                decoration:  _inputDec('Full name (optional)'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller:  _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration:  _inputDec('Email address'),
                    onSubmitted: (_) => _addSigner(),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _addSigner,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation:       0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                  ),
                  child: const Icon(Icons.add, size: 20),
                ),
              ]),
              if (_inputError != null) ...[
                const SizedBox(height: 4),
                Text(_inputError!,
                    style: TextStyle(fontSize: 12, color: Colors.red.shade600)),
              ],
              // Signer list
              if (_signers.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                ..._signers.map(
                  (s) => ListTile(
                    dense:   true,
                    leading: CircleAvatar(
                      radius:          14,
                      backgroundColor: AppColors.primary.withOpacity(0.12),
                      child: Text(
                        (s.name.isNotEmpty ? s.name : s.email)
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary),
                      ),
                    ),
                    title: Text(
                      s.name.isNotEmpty ? s.name : s.email,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    subtitle: s.name.isNotEmpty
                        ? Text(s.email,
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade500))
                        : null,
                    trailing: IconButton(
                      icon:       const Icon(Icons.close, size: 16),
                      color:      Colors.grey.shade500,
                      onPressed:  () => _removeSigner(s),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                Center(
                  child: Text('No signers added yet.',
                      style:
                          TextStyle(fontSize: 12, color: Colors.grey.shade500)),
                ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancel',
              style: TextStyle(color: Colors.grey.shade700)),
        ),
        ElevatedButton(
          onPressed: _signers.isEmpty
              ? null
              : () => Navigator.pop(context, _signers),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade200,
            disabledForegroundColor: Colors.grey.shade400,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            _signers.isEmpty
                ? 'Send'
                : 'Send to ${_signers.length}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ── WebView screen ────────────────────────────────────────────────────────────

class _DssWebViewScreen extends StatefulWidget {
  final String url;
  final String title;
  final String accessToken;
  final String refreshToken;

  const _DssWebViewScreen({
    required this.url,
    required this.title,
    required this.accessToken,
    required this.refreshToken,
  });

  @override
  State<_DssWebViewScreen> createState() => _DssWebViewScreenState();
}

class _DssWebViewScreenState extends State<_DssWebViewScreen> {
  late final WebViewController _controller;
  bool _loading    = true;
  bool _shimLoaded = false;

  @override
  void initState() {
    super.initState();

    final safeAccess  = widget.accessToken .replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final safeRefresh = widget.refreshToken.replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    final shimHtml = '''
<!DOCTYPE html>
<html>
<head>
<script>
  try {
    var tokens = JSON.stringify({
      "access":  "$safeAccess",
      "refresh": "$safeRefresh"
    });
    sessionStorage.setItem('authTokens', tokens);
  } catch(e) {}
  window.location.replace('${widget.url}');
</script>
</head>
<body></body>
</html>
''';

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (url.startsWith('https://dss.alignsys.tech')) {
            _shimLoaded = true;
          }
        },
        onPageFinished: (url) async {
          if (_shimLoaded) {
            await _controller.runJavaScript(
              "try {"
              "  var t = JSON.stringify({"
              "    access:  '$safeAccess',"
              "    refresh: '$safeRefresh'"
              "  });"
              "  sessionStorage.setItem('authTokens', t);"
              "} catch(e) {}",
            );
          }
          if (mounted) setState(() => _loading = false);
        },
      ))
      ..loadHtmlString(shimHtml, baseUrl: 'https://dss.alignsys.tech');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: Text(
          widget.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 15),
        ),
        actions: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(right: 16),
              child: Center(
                child: SizedBox(
                  height: 18, width: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: WebViewWidget(controller: _controller),
    );
  }
}