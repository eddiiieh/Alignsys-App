import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_service.dart';

/// Wrap any Scaffold body with this to get an automatic snackbar
/// when connectivity drops to a genuinely weak or offline state,
/// and another when it recovers.
///
/// Usage:
///   body: NetworkBanner(child: YourWidget()),
class NetworkBanner extends StatefulWidget {
  final Widget child;
  const NetworkBanner({super.key, required this.child});

  @override
  State<NetworkBanner> createState() => _NetworkBannerState();
}

class _NetworkBannerState extends State<NetworkBanner> {
  NetworkQuality? _lastQuality;

  void _handleQualityChange(NetworkQuality quality) {
    if (_lastQuality == quality) return;

    final wasGood = _lastQuality == NetworkQuality.good || _lastQuality == null;
    final isGood = quality == NetworkQuality.good;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (quality == NetworkQuality.offline) {
        _showStatusSnackbar(
          icon: Icons.wifi_off_rounded,
          message: "You're offline. Some content can't be loaded.",
          backgroundColor: const Color(0xFFef4444),
        );
      }

      // Only announce slow on the transition down from good, not on
      // every repeated slow reading while it stays slow.
      if (quality == NetworkQuality.slow && wasGood) {
        final network = context.read<NetworkService>();
        final latency = network.latencyMs;
        _showStatusSnackbar(
          icon: Icons.wifi_find_rounded,
          message: latency != null
              ? 'Slow connection detected (${latency}ms). Things may take longer to load.'
              : 'Slow connection detected. Things may take longer to load.',
          backgroundColor: const Color(0xFFf59e0b),
        );
      }

      if (isGood && !wasGood) {
        _showStatusSnackbar(
          icon: Icons.wifi,
          message: 'Back online',
          backgroundColor: const Color(0xFF22c55e),
        );
      }
    });

    _lastQuality = quality;
  }

  void _showStatusSnackbar({
    required IconData icon,
    required String message,
    required Color backgroundColor,
  }) {
    ScaffoldMessenger.of(context).clearSnackBars();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: Colors.white, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message, style: const TextStyle(fontSize: 13)),
            ),
          ],
        ),
        backgroundColor: backgroundColor,
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        margin: const EdgeInsets.all(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkService>(
      builder: (context, network, _) {
        _handleQualityChange(network.quality);
        return widget.child;
      },
    );
  }
}

/// Wraps a widget and dims it + shows a message when offline.
/// Use this on specific sections like lists of items or views.
///
/// Usage:
///   OfflineSection(label: 'Recent Items', child: YourListWidget())
class OfflineSection extends StatelessWidget {
  final Widget child;
  final String label;

  const OfflineSection({
    super.key,
    required this.child,
    this.label = 'This section',
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkService>(
      builder: (context, network, _) {
        final offline = network.isOffline;
        return Stack(
          children: [
            AnimatedOpacity(
              opacity: offline ? 0.3 : 1.0,
              duration: const Duration(milliseconds: 400),
              child: IgnorePointer(
                ignoring: offline,
                child: child,
              ),
            ),
            if (offline)
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off_rounded,
                          size: 20, color: Colors.red[300]!.withOpacity(0.7)),
                      const SizedBox(height: 8),
                      Text(
                        '$label requires internet',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.red[200],
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Reconnect to load this content',
                        style: TextStyle(fontSize: 11, color: Colors.white30),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}