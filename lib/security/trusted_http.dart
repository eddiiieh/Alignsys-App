import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

class TrustedHttpOverrides extends HttpOverrides {
  final SecurityContext securityContext;

  TrustedHttpOverrides(this.securityContext);

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(securityContext);
  }
}

Future<void> initializeTrustedCertificates() async {
  final data = await rootBundle.load(
    'assets/certs/sectigo_r46.crt',
  );

  final context = SecurityContext(withTrustedRoots: true);

  context.setTrustedCertificatesBytes(
    Uint8List.view(data.buffer),
  );

  HttpOverrides.global = TrustedHttpOverrides(context);

  print('✅ Sectigo Root R46 loaded');
}