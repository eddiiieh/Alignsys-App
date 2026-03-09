import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

enum NetworkQuality { good, slow, offline }

class NetworkService extends ChangeNotifier {
  NetworkQuality _quality = NetworkQuality.good;
  int? _latencyMs;
  StreamSubscription? _connectivitySub;
  Timer? _pingTimer;

  NetworkQuality get quality => _quality;
  int? get latencyMs => _latencyMs;
  bool get isOffline => _quality == NetworkQuality.offline;
  bool get isSlow => _quality == NetworkQuality.slow;

  NetworkService() {
    _init();
  }

  void _init() {
    // Listen for connectivity changes
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) {
      final hasConnection = results.any((r) => r != ConnectivityResult.none);
      if (!hasConnection) {
        _setQuality(NetworkQuality.offline, null);
      } else {
        _measureLatency();
      }
    });

    // Ping every 8 seconds to detect slow connections
    _pingTimer = Timer.periodic(const Duration(seconds: 8), (_) => _measureLatency());

    // Initial check
    _measureLatency();
  }

  Future<void> _measureLatency() async {
    final stopwatch = Stopwatch()..start();
    try {
      final socket = await Socket.connect('8.8.8.8', 53,
          timeout: const Duration(seconds: 5));
      socket.destroy();
      stopwatch.stop();

      final rtt = stopwatch.elapsedMilliseconds;
      NetworkQuality quality;

      if (rtt > 400) {
        quality = NetworkQuality.slow;
      } else {
        quality = NetworkQuality.good;
      }

      _setQuality(quality, rtt);
    } catch (_) {
      stopwatch.stop();
      _setQuality(NetworkQuality.offline, null);
    }
  }

  void _setQuality(NetworkQuality quality, int? latencyMs) {
    if (_quality == quality && _latencyMs == latencyMs) return;
    _quality = quality;
    _latencyMs = latencyMs;
    notifyListeners();
  }

  @override
  void dispose() {
    _connectivitySub?.cancel();
    _pingTimer?.cancel();
    super.dispose();
  }
}