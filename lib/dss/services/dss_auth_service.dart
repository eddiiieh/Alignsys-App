// lib/dss/services/dss_auth_service.dart
// ignore_for_file: avoid_print

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

class DssUserInfo {
  final int userId;
  final String email;
  final String companyId;
  final String company;
  final String phone;
  final List<String> groups;

  const DssUserInfo({
    required this.userId,
    required this.email,
    required this.companyId,
    required this.company,
    required this.phone,
    required this.groups,
  });

  factory DssUserInfo.fromJwtPayload(Map<String, dynamic> payload) {
    int toInt(dynamic v) {
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v) ?? 0;
      return 0;
    }

    List<String> toStrList(dynamic v) {
      if (v is List) return v.map((e) => e.toString()).toList();
      if (v is String) return [v];
      return [];
    }

    return DssUserInfo(
      userId: toInt(payload['user_id'] ?? payload['userId'] ?? payload['sub']),
      email: (payload['email'] ?? '').toString(),
      companyId: (payload['companyid'] ?? payload['companyId'] ?? '').toString(),
      company: (payload['company'] ?? '').toString(),
      phone: (payload['phone'] ?? '').toString(),
      groups: toStrList(payload['groups']),
    );
  }
}

class DssAuthService {
  static const _baseAuthUrl = 'https://dssauth.alignsys.tech/api/token/';
  static const _refreshUrl  = 'https://dssauth.alignsys.tech/api/token/refresh/';

  String? accessToken;
  String? refreshToken;
  DssUserInfo? userInfo;

  Map<String, dynamic>? decodePayload(String token) {
    try {
      final parts = token.split('.');
      if (parts.length != 3) return null;
      final normalized = base64Url.normalize(parts[1]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      return json.decode(decoded) as Map<String, dynamic>;
    } catch (e) {
      print('❌ DSS JWT decode error: $e');
      return null;
    }
  }

  Future<bool> loginWithEmailPassword(String email, String password) async {
    final response = await http.post(
      Uri.parse(_baseAuthUrl),
      headers: const {'Content-Type': 'application/json'},
      body: json.encode({'email': email, 'password': password}),
    );
    print('📡 DSS login status: ${response.statusCode}');
    if (response.statusCode == 401) return false;
    if (response.statusCode != 200) {
      throw Exception('DSS auth failed: ${response.statusCode}');
    }
    final data = json.decode(response.body);
    final access  = data['access']  as String?;
    final refresh = data['refresh'] as String?;
    if (access == null || access.isEmpty) return false;
    accessToken  = access;
    refreshToken = refresh;
    final payload = decodePayload(access);
    if (payload != null) userInfo = DssUserInfo.fromJwtPayload(payload);
    await _persist();
    return true;
  }

  Future<bool> refreshAccessToken() async {
    if (refreshToken == null || refreshToken!.isEmpty) return false;
    try {
      final response = await http.post(
        Uri.parse(_refreshUrl),
        headers: const {'Content-Type': 'application/json'},
        body: json.encode({'refresh': refreshToken}),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final newAccess = data['access'] as String?;
        if (newAccess != null && newAccess.isNotEmpty) {
          accessToken = newAccess;
          final payload = decodePayload(newAccess);
          if (payload != null) userInfo = DssUserInfo.fromJwtPayload(payload);
          await _persist();
          return true;
        }
      }
    } catch (e) {
      print('❌ DSS token refresh error: $e');
    }
    return false;
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    if (accessToken  != null) await prefs.setString('dss_access_token',  accessToken!);
    if (refreshToken != null) await prefs.setString('dss_refresh_token', refreshToken!);
    if (userInfo     != null) {
      await prefs.setInt('dss_user_id',        userInfo!.userId);
      await prefs.setString('dss_company_id',  userInfo!.companyId);
    }
  }

  Future<bool> loadFromPrefs() async {
    final prefs  = await SharedPreferences.getInstance();
    accessToken  = prefs.getString('dss_access_token');
    refreshToken = prefs.getString('dss_refresh_token');
    if (accessToken != null) {
      final payload = decodePayload(accessToken!);
      if (payload != null) userInfo = DssUserInfo.fromJwtPayload(payload);
    }
    return accessToken != null && accessToken!.isNotEmpty;
  }

  Future<void> logout() async {
    accessToken  = null;
    refreshToken = null;
    userInfo     = null;
    final prefs  = await SharedPreferences.getInstance();
    await prefs.remove('dss_access_token');
    await prefs.remove('dss_refresh_token');
    await prefs.remove('dss_user_id');
    await prefs.remove('dss_company_id');
  }

  bool get isLoggedIn => accessToken != null && accessToken!.isNotEmpty;
}