// lib/dss/widgets/send_for_signing_card.dart
// Drop into ObjectDetailsScreen's ListView after _previewCard, before _commentsCard.
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/mfiles_service.dart';
import '../../models/view_object.dart';
import '../../models/object_file.dart';
import '../../theme/app_colors.dart';
import '../services/dss_auth_service.dart';
import '../services/dss_api_service.dart';
import '../screens/dss_dashboard_screen.dart';

class SendForSigningCard extends StatefulWidget {
  final ViewObject                  obj;
  final Future<List<ObjectFile>>    filesFuture;

  const SendForSigningCard({
    super.key,
    required this.obj,
    required this.filesFuture,
  });

  @override
  State<SendForSigningCard> createState() => _SendForSigningCardState();
}

class _SendForSigningCardState extends State<SendForSigningCard> {
  bool    _busy    = false;
  String? _error;

  late DssApiService  _api;
  late DssAuthService _auth;

  @override
  void initState() {
    super.initState();
    final mfiles = context.read<MFilesService>();
    _auth = DssAuthService()
      ..accessToken  = mfiles.dssAccessToken
      ..refreshToken = mfiles.dssRefreshToken;

    if (mfiles.dssAccessToken != null) {
      final payload = _auth.decodePayload(mfiles.dssAccessToken!);
      if (payload != null) {
        _auth.userInfo = DssUserInfo.fromJwtPayload(payload);
      }
    }
    _api = DssApiService(authService: _auth);
  }

  // ── Entry: show action sheet ──────────────────────────────────────────────

  void _onTap(List<ObjectFile> files) async {
    final mfiles = context.read<MFilesService>();
    if (!mfiles.isDssAvailable) {
      _showSnack('DSS is not available — please log out and back in.',
          isError: true);
      return;
    }
    if (files.isEmpty) {
      _showSnack('This document has no files to send for signing.',
          isError: true);
      return;
    }

    // If there are multiple files, ask which one first
    ObjectFile? target;
    if (files.length == 1) {
      target = files.first;
    } else {
      target = await _pickFile(files);
      if (target == null) return;
    }

    if (!mounted) return;
    _showActionSheet(target);
  }

  // ── Action sheet ──────────────────────────────────────────────────────────

  void _showActionSheet(ObjectFile target) {
    showModalBottomSheet(
      context:         context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color:        Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            // File badge
            Row(children: [
              const Icon(Icons.insert_drive_file_outlined,
                  size: 18, color: AppColors.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  target.fileTitle.isNotEmpty
                      ? target.fileTitle
                      : 'File ${target.fileId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                '.${target.extension}  v${target.fileVersion}',
                style: TextStyle(
                    fontSize: 11, color: Colors.grey.shade500),
              ),
            ]),
            const SizedBox(height: 16),
            _sheetAction(
              icon:  Icons.draw_outlined,
              label: 'Sign Now',
              sub:   'Open the signing session immediately',
              onTap: () {
                Navigator.pop(context);
                _handleSignNow(target);
              },
            ),
            const SizedBox(height: 10),
            _sheetAction(
              icon:  Icons.group_outlined,
              label: 'Send to Others',
              sub:   'Request signatures from specific people',
              onTap: () {
                Navigator.pop(context);
                _handleSendToOthers(target);
              },
            ),
            const SizedBox(height: 10),
            _sheetAction(
              icon:  Icons.bookmark_border_outlined,
              label: 'Save for Later',
              sub:   'Register in DSS without sending',
              onTap: () {
                Navigator.pop(context);
                _handleSaveLater(target);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Action: Sign Now ──────────────────────────────────────────────────────

  Future<void> _handleSignNow(ObjectFile target) async {
    final dssEmail = _auth.userInfo?.email ?? '';
    if (dssEmail.isEmpty) {
      _showSnack('Cannot determine your DSS email. Please log out and back in.',
          isError: true);
      return;
    }

    final result = await _post(target: target, signerEmail: dssEmail);
    if (result == null || !mounted) return;

    if (result.url != null && result.url!.isNotEmpty) {
      _openWebView(url: result.url!, title: widget.obj.title);
    } else {
      _showSnack('Document registered in DSS. Open your Inbox to sign.');
    }
  }

  // ── Action: Send to Others ────────────────────────────────────────────────

  Future<void> _handleSendToOthers(ObjectFile target) async {
    final signers = await _showSignerDialog();
    if (signers == null || signers.isEmpty) return;

    final signerEmail = signers.map((s) => s.email).join(',');
    final result      = await _post(target: target, signerEmail: signerEmail);
    if (result == null || !mounted) return;

    final dssEmail = (_auth.userInfo?.email ?? '').toLowerCase().trim();
    final isSelf   = signers.any(
        (s) => s.email.toLowerCase().trim() == dssEmail);

    if (isSelf && result.url != null && result.url!.isNotEmpty) {
      _openWebView(url: result.url!, title: widget.obj.title);
    } else {
      final n = signers.length;
      _showSnack('Sent to $n signer${n == 1 ? '' : 's'} successfully.');
    }
  }

  // ── Action: Save for Later ────────────────────────────────────────────────

  Future<void> _handleSaveLater(ObjectFile target) async {
    final dssEmail = _auth.userInfo?.email ?? '';
    final result   = await _post(target: target, signerEmail: dssEmail);
    if (result == null || !mounted) return;
    _showSnack('Document saved to DSS for later.');
  }

  // ── Shared post helper ────────────────────────────────────────────────────

  Future<DssPostResult?> _post({
    required ObjectFile target,
    required String     signerEmail,
  }) async {
    setState(() { _busy = true; _error = null; });
    try {
      final mfiles   = context.read<MFilesService>();
      final displayId = int.tryParse(widget.obj.displayId) ?? widget.obj.id;

      final result = await _api.postObjectFile(
        objectId:    displayId,
        classId:     widget.obj.classId,
        fileId:      target.fileId,
        versionId:   target.fileVersion,
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

  // ── File picker (multi-file objects) ──────────────────────────────────────

  Future<ObjectFile?> _pickFile(List<ObjectFile> files) {
    return showModalBottomSheet<ObjectFile>(
      context:         context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        decoration: const BoxDecoration(
          color:        Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 32),
        child: Column(
          mainAxisSize:       MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color:        Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Choose file to sign',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            ...files.map((f) => ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined,
                      color: AppColors.primary),
                  title: Text(
                    f.fileTitle.isNotEmpty ? f.fileTitle : 'File ${f.fileId}',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('.${f.extension}  •  v${f.fileVersion}',
                      style: TextStyle(
                          fontSize: 12, color: Colors.grey.shade500)),
                  onTap: () => Navigator.pop(context, f),
                )),
          ],
        ),
      ),
    );
  }

  // ── Signer dialog ─────────────────────────────────────────────────────────

  Future<List<DssSigner>?> _showSignerDialog() {
    return showDialog<List<DssSigner>>(
      context: context,
      builder: (_) => const _SignerDialog(),
    );
  }

  // ── WebView ───────────────────────────────────────────────────────────────

  void _openWebView({required String url, required String title}) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => _DssWebViewScreen(
          url:          url,
          title:        'Sign: $title',
          accessToken:  _auth.accessToken  ?? '',
          refreshToken: _auth.refreshToken ?? '',
        ),
      ),
    );
  }

  // ── Dashboard shortcut ────────────────────────────────────────────────────

  void _openDssDashboard() {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            title: const Text('Digital Signing'),
          ),
          body: const DssDashboardScreen(),
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

  Widget _sheetAction({
    required IconData     icon,
    required String       label,
    required String       sub,
    required VoidCallback onTap,
    Color?                color,
  }) {
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
            Icon(Icons.chevron_right,
                size: 18, color: c.withOpacity(0.5)),
          ]),
        ),
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final mfiles = context.watch<MFilesService>();
    if (!mfiles.isDssAvailable) return const SizedBox.shrink();

    return Container(
      padding:    const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color:        Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:       Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────
          Row(children: [
            Container(
              padding:    const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color:        AppColors.primary.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.draw_outlined,
                  size: 16, color: AppColors.primary),
            ),
            const SizedBox(width: 8),
            const Text('Digital Signing',
                style:
                    TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
            const Spacer(),
            TextButton(
              onPressed: _openDssDashboard,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                textStyle: const TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w600),
              ),
              child: const Text('Open DSS →'),
            ),
          ]),
          const SizedBox(height: 10),
          // ── Send button ───────────────────────────────────────────────
          FutureBuilder<List<ObjectFile>>(
            future: widget.filesFuture,
            builder: (context, snap) {
              final files    = snap.data ?? [];
              final hasFiles = files.isNotEmpty;
              final loading  =
                  snap.connectionState == ConnectionState.waiting;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: (_busy || !hasFiles || loading)
                          ? null
                          : () => _onTap(files),
                      style: ElevatedButton.styleFrom(
                        backgroundColor:        AppColors.primary,
                        foregroundColor:        Colors.white,
                        disabledBackgroundColor: Colors.grey.shade200,
                        disabledForegroundColor: Colors.grey.shade400,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                      ),
                      icon: _busy
                          ? const SizedBox(
                              height: 16, width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                    Colors.white),
                              ))
                          : const Icon(Icons.send_outlined, size: 18),
                      label: Text(
                        _busy
                            ? 'Processing…'
                            : loading
                                ? 'Loading files…'
                                : hasFiles
                                    ? 'Send for Signing'
                                    : 'No files to sign',
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  // Error banner
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding:    const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color:        Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border:
                            Border.all(color: Colors.red.shade200),
                      ),
                      child: Row(children: [
                        Icon(Icons.error_outline,
                            size: 14, color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_error!,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.red.shade700)),
                        ),
                      ]),
                    ),
                  ],
                ],
              );
            },
          ),
        ],
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
          email: email, name: name, order: _signers.length + 1));
      _emailCtrl.clear();
      _nameCtrl.clear();
    });
  }

  void _removeSigner(String email) {
    setState(() {
      _signers.removeWhere((s) => s.email == email);
      for (var i = 0; i < _signers.length; i++) {
        _signers[i] = DssSigner(
            email: _signers[i].email,
            name:  _signers[i].name,
            order: i + 1);
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
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        isDense: true,
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape:          RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16)),
      contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      title: const Text('Send to Others',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize:       MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller:         _nameCtrl,
                decoration:         _inputDec('Full name (optional)'),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller:   _emailCtrl,
                    keyboardType: TextInputType.emailAddress,
                    decoration:   _inputDec('Email address'),
                    onSubmitted:  (_) => _addSigner(),
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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 13),
                  ),
                  child: const Icon(Icons.add, size: 20),
                ),
              ]),
              if (_inputError != null) ...[
                const SizedBox(height: 4),
                Text(_inputError!,
                    style: TextStyle(
                        fontSize: 12, color: Colors.red.shade600)),
              ],
              if (_signers.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                ..._signers.map((s) => ListTile(
                      dense:   true,
                      leading: CircleAvatar(
                        radius:          14,
                        backgroundColor:
                            AppColors.primary.withOpacity(0.12),
                        child: Text(
                          (s.name.isNotEmpty ? s.name : s.email)
                              .substring(0, 1)
                              .toUpperCase(),
                          style: const TextStyle(
                              fontSize:   12,
                              fontWeight: FontWeight.w700,
                              color:      AppColors.primary),
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
                                  fontSize: 11,
                                  color:    Colors.grey.shade500))
                          : null,
                      trailing: IconButton(
                        icon:          const Icon(Icons.close, size: 16),
                        color:         Colors.grey.shade500,
                        visualDensity: VisualDensity.compact,
                        onPressed:     () => _removeSigner(s.email),
                      ),
                    )),
              ] else ...[
                const SizedBox(height: 12),
                Center(
                  child: Text('No signers added yet.',
                      style: TextStyle(
                          fontSize: 12,
                          color:    Colors.grey.shade500)),
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
              : () => Navigator.pop(context, List<DssSigner>.from(_signers)),
          style: ElevatedButton.styleFrom(
            backgroundColor:        AppColors.primary,
            foregroundColor:        Colors.white,
            disabledBackgroundColor: Colors.grey.shade200,
            disabledForegroundColor: Colors.grey.shade400,
            elevation: 0,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(
            _signers.isEmpty ? 'Send' : 'Send to ${_signers.length}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

// ── WebView screen ─────────────────────────────────────────────────────────────

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
        title: Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15)),
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