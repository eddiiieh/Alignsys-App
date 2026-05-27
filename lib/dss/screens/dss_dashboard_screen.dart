// lib/dss/screens/dss_dashboard_screen.dart
// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../services/mfiles_service.dart';
import '../../theme/app_colors.dart';
import '../services/dss_auth_service.dart';

// ── Dashboard — renders the DSS web app directly in a WebView ────────────────
//
// No native tab UI or document list — DSS has its own full dashboard.
// The WebView IS the UI. The Upload FAB is added by the parent (home_screen).
//
// Token injection strategy:
//   1. A shim HTML page sets sessionStorage AND localStorage authTokens
//      synchronously before the DSS SPA boots.
//   2. onPageFinished re-injects on every navigation for SPA route changes.
//   3. Both storage types are written so auth survives cold restarts.

class DssDashboardScreen extends StatefulWidget {
  const DssDashboardScreen({super.key});

  @override
  State<DssDashboardScreen> createState() => _DssDashboardScreenState();
}

class _DssDashboardScreenState extends State<DssDashboardScreen> {
  late final WebViewController _controller;
  bool _loading    = true;
  bool _shimLoaded = false;
  bool _hasError   = false;

  @override
  void initState() {
    super.initState();
    final mfiles = context.read<MFilesService>();

    final auth = DssAuthService()
      ..accessToken  = mfiles.dssAccessToken
      ..refreshToken = mfiles.dssRefreshToken;

    final safeAccess  = (auth.accessToken  ?? '').replaceAll(r'\', r'\\').replaceAll("'", r"\'");
    final safeRefresh = (auth.refreshToken ?? '').replaceAll(r'\', r'\\').replaceAll("'", r"\'");

    // Shim: sets auth in BOTH sessionStorage and localStorage so it survives
    // cold restarts, then immediately redirects to the DSS root.
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
    localStorage.setItem('authTokens',   tokens);
  } catch(e) {}
  window.location.replace('https://dss.alignsys.tech');
</script>
</head>
<body></body>
</html>
''';

    // Re-injected on every page finish to handle SPA route changes
    final reInjectJs =
        "try {"
        "  var t = JSON.stringify({"
        "    access:  '$safeAccess',"
        "    refresh: '$safeRefresh'"
        "  });"
        "  sessionStorage.setItem('authTokens', t);"
        "  localStorage.setItem('authTokens',   t);"
        "} catch(e) {}";

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (url) {
          if (url.startsWith('https://dss.alignsys.tech')) {
            _shimLoaded = true;
          }
          if (mounted) setState(() => _loading = true);
        },
        onPageFinished: (url) async {
          if (_shimLoaded) {
            await _controller.runJavaScript(reInjectJs);
          }
          if (mounted) setState(() { _loading = false; _hasError = false; });
        },
        onWebResourceError: (_) {
          if (mounted) setState(() { _loading = false; _hasError = true; });
        },
      ))
      ..loadHtmlString(shimHtml, baseUrl: 'https://dss.alignsys.tech');
  }

  void _reload() {
    setState(() { _loading = true; _hasError = false; });
    _controller.reload();
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) return _buildError();
    return Stack(
      children: [
        WebViewWidget(controller: _controller),
        if (_loading)
          const Center(child: CircularProgressIndicator()),
      ],
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
            const Text('Could not load DSS',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            Text('Check your connection and try again.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: _reload,
              icon:  const Icon(Icons.refresh),
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