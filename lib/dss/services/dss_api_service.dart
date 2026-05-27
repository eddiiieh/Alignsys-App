// lib/dss/services/dss_api_service.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:http/http.dart' as http;

import 'dss_auth_service.dart';

// ── Models ──────────────────────────────────────────────────────────────────

enum DssDocumentTab { inbox, outbox, complete, voided, saved, trashed }

extension DssDocumentTabExt on DssDocumentTab {
  String get apiValue {
    switch (this) {
      case DssDocumentTab.inbox:    return 'inbox';
      case DssDocumentTab.outbox:   return 'outbox';
      case DssDocumentTab.complete: return 'complete';
      case DssDocumentTab.voided:   return 'voided';
      case DssDocumentTab.saved:    return 'saved';
      case DssDocumentTab.trashed:  return 'trashed';
    }
  }

  String get label {
    switch (this) {
      case DssDocumentTab.inbox:    return 'Inbox';
      case DssDocumentTab.outbox:   return 'Outbox';
      case DssDocumentTab.complete: return 'Complete';
      case DssDocumentTab.voided:   return 'Voided';
      case DssDocumentTab.saved:    return 'Saved';
      case DssDocumentTab.trashed:  return 'Trashed';
    }
  }
}

class DssSigner {
  final String email;
  final String name;
  final int order;

  const DssSigner({
    required this.email,
    required this.name,
    this.order = 1,
  });
}

class DssPostResult {
  final bool success;
  final String? message;
  final String? documentGuid;
  final String? url;

  const DssPostResult({
    required this.success,
    this.message,
    this.documentGuid,
    this.url,
  });
}

// ── Service ──────────────────────────────────────────────────────────────────

class DssApiService {
  // ── STEP A: Try with /api prefix (active) ─────────────────────────────────
  static const _baseUrl = 'https://api.alignsys.tech/api';
  //
  // ── STEP B: If still getting HTML, comment above and uncomment this ────────
  // static const _baseUrl = 'https://dss.alignsys.tech';

  final DssAuthService authService;

  DssApiService({required this.authService});

  Map<String, String> get _jsonHeaders {
    final token = authService.accessToken;
    return {
      'Content-Type': 'application/json',
      'accept':        'application/json',
      if (token != null) 'Authorization': 'Bearer $token',
    };
  }

  Future<http.Response> _request(
    Future<http.Response> Function() call,
  ) async {
    http.Response response = await call();
    if (response.statusCode == 401) {
      final refreshed = await authService.refreshAccessToken();
      if (refreshed) response = await call();
    }
    return response;
  }

  Future<DssPostResult> postObjectFile({
    required int    objectId,
    required int    classId,
    required int    fileId,
    required int    versionId,
    required String vaultGuid,
    required String signerEmail,
    required int    dssUserId,
  }) async {
    final uri = Uri.parse('$_baseUrl/objectinstance/DSSPostObjectFile');

    // JSON body (int values kept as int — some APIs reject strings for numeric fields)
    final jsonBody = {
      'objectid':    objectId,
      'classId':     classId,
      'fileid':      fileId,
      'versionID':   versionId,
      'vaultGuid':   vaultGuid,
      'signerEmail': signerEmail,
      'userID':      dssUserId,
    };

    print('📤 DSSPostObjectFile url:  $uri');
    print('📤 DSSPostObjectFile body: $jsonBody');

    try {
      // ════════════════════════════════════════════════════════════════════
      // APPROACH 2 — POST with JSON body  ← ACTIVE
      // ════════════════════════════════════════════════════════════════════
      final response = await _request(
        () => http.post(
          uri,
          headers: _jsonHeaders,
          body:    json.encode(jsonBody),
        ),
      );

      // ════════════════════════════════════════════════════════════════════
      // APPROACH 3 — POST with form-encoded body
      // Comment out Approach 2 and uncomment this if you still get HTML back.
      // ════════════════════════════════════════════════════════════════════
      /*
      final response = await _request(
        () => http.post(
          uri,
          headers: _formHeaders,
          body:    formBody,
        ),
      );
      */

      print('📡 DSSPostObjectFile status: ${response.statusCode}');

      final body = response.body.trim();

      // ── HTML guard: if we're still getting the React shell, the route
      //    is wrong. Show a clear error instead of a misleading snackbar.
      if (body.startsWith('<!') || body.startsWith('<html')) {
        print('⚠️  Got HTML back — wrong route or method. '
              'Try the other _baseUrl or Approach 3.');
        return const DssPostResult(
          success: false,
          message: 'Server returned an HTML page — wrong endpoint or method. '
                   'Check the terminal for which combination to try next.',
        );
      }

      print('📡 DSSPostObjectFile body: $body');

      if (response.statusCode == 200 || response.statusCode == 201) {
        dynamic decoded;
        try {
          decoded = json.decode(body);
        } catch (_) {}

        String? guid;
        String? url;

        if (decoded is Map) {
          guid = (decoded['guid'] ??
                  decoded['documentGuid'] ??
                  decoded['id'])
              ?.toString();

          url = (decoded['url'] ??
                  decoded['signingUrl'] ??
                  decoded['signing_url'] ??
                  decoded['redirectUrl'] ??
                  decoded['redirect_url'])
              ?.toString();
        }

        // Fallback: bare URL string in body
        if (url == null && body.startsWith('http')) {
          url = body;
        }

        return DssPostResult(success: true, documentGuid: guid, url: url);
      }

      return DssPostResult(
        success: false,
        message: 'Server returned ${response.statusCode}: $body',
      );
    } catch (e) {
      return DssPostResult(success: false, message: 'Error: $e');
    }
  }
}