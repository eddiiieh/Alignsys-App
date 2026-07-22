// lib/dss/screens/dss_signing_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/mfiles_service.dart';
import '../../theme/app_colors.dart';

/// Opens a specific DSS signing URL in a WebView.
/// When closed, the caller can refresh the document.
class DssSigningScreen extends StatefulWidget {
  final String signingUrl;

  const DssSigningScreen({super.key, required this.signingUrl});

  @override
  State<DssSigningScreen> createState() => _DssSigningScreenState();
}

class _DssSigningScreenState extends State<DssSigningScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _hasError = false;

  @override
void initState() {
  super.initState();

  final mfiles = context.read<MFilesService>();

  // Use DSS tokens if available, otherwise fall back to the normal EDMS tokens.
  final accessToken =
      (mfiles.dssAccessToken?.isNotEmpty == true)
          ? mfiles.dssAccessToken!
          : (mfiles.accessToken ?? '');

  final refreshToken =
      (mfiles.dssRefreshToken?.isNotEmpty == true)
          ? mfiles.dssRefreshToken!
          : (mfiles.refreshToken ?? '');

  /*debugPrint('================ DSS WEBVIEW TOKENS ================');
  debugPrint('Access token empty : ${accessToken.isEmpty}');
  debugPrint('Refresh token empty: ${refreshToken.isEmpty}');
  debugPrint(
      'Access preview : ${accessToken.length > 30 ? accessToken.substring(0, 30) : accessToken}');
  debugPrint(
      'Refresh preview: ${refreshToken.length > 30 ? refreshToken.substring(0, 30) : refreshToken}');
  debugPrint('====================================================');*/

  final safeAccess = accessToken
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'");

  final safeRefresh = refreshToken
      .replaceAll(r'\', r'\\')
      .replaceAll("'", r"\'");

  final reInjectJs = """
    try {
      var t = JSON.stringify({
        access: '$safeAccess',
        refresh: '$safeRefresh'
      });
      // sessionStorage.setItem('authTokens', t);
      // localStorage.setItem('authTokens', t);
      // console.log('Injected authTokens:', t);
    } catch(e) {
      console.error(e);
    }
  """;

  final shimHtml = """
<!DOCTYPE html>
<html>
<head>
<script>
try {
  var t = JSON.stringify({
    access: "$safeAccess",
    refresh: "$safeRefresh"
  });

  //sessionStorage.setItem('authTokens', t);
  //localStorage.setItem('authTokens', t);

  //console.log('Injected authTokens:', t);

} catch(e) {
  console.error(e);
}

window.location.replace("${widget.signingUrl}");
</script>
</head>
<body></body>
</html>
""";

  _controller = WebViewController()
    ..setJavaScriptMode(JavaScriptMode.unrestricted)
    ..setNavigationDelegate(
      NavigationDelegate(
        onPageStarted: (_) {
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (_) async {
          await _controller.runJavaScript(reInjectJs);
          if (mounted) {
            setState(() {
              _loading = false;
              _hasError = false;
            });
          }
        },
        onWebResourceError: (_) {
          if (mounted) {
            setState(() {
              _loading = false;
              _hasError = true;
            });
          }
        },
      ),
    )
    ..loadHtmlString(
      shimHtml,
      baseUrl: 'https://dss.alignsys.tech',
    );
}

  void _reload() {
    setState(() {
      _loading = true;
      _hasError = false;
    });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surfaceLight,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        title: const Text('Sign Document'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context, true), // true = signed
          ),
        ],
      ),
      body: _hasError
          ? _buildError()
          : Stack(
              children: [
                WebViewWidget(controller: _controller),
                if (_loading)
                  const Center(child: CircularProgressIndicator()),
              ],
            ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_outlined,
                size: 48, color: Colors.red.shade300),
            const SizedBox(height: 16),
            const Text('Could not load signing page',
                style:
                    TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Check your connection and try again.',
                style: TextStyle(
                    fontSize: 13, color: Colors.grey.shade500),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _reload,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}