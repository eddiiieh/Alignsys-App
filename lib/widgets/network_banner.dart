import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/network_service.dart';

/// Wrap any Scaffold body with this to get an automatic
/// top banner when offline or on a slow connection.
///
/// Usage:
///   body: NetworkBanner(child: YourWidget()),
class NetworkBanner extends StatefulWidget {
  final Widget child;
  const NetworkBanner({super.key, required this.child});

  @override
  State<NetworkBanner> createState() => _NetworkBannerState();
}

class _NetworkBannerState extends State<NetworkBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  NetworkQuality? _lastQuality;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleQualityChange(NetworkQuality quality) {
    if (_lastQuality == quality) return;

    final wasGood = _lastQuality == NetworkQuality.good || _lastQuality == null;
    final isGood = quality == NetworkQuality.good;

    if (!isGood && wasGood) {
      _controller.forward();
    } else if (isGood && !wasGood) {
      _controller.reverse();
    }

    // Show "back online" snackbar
    if (isGood && !wasGood) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi, color: Colors.white, size: 16),
                SizedBox(width: 8),
                Text('Back online', style: TextStyle(fontSize: 13)),
              ],
            ),
            backgroundColor: const Color(0xFF22c55e),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            margin: const EdgeInsets.all(12),
          ),
        );
      });
    }

    _lastQuality = quality;
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<NetworkService>(
      builder: (context, network, _) {
        _handleQualityChange(network.quality);

        return Column(
          children: [
            SlideTransition(
              position: _slideAnimation,
              child: _NetworkStatusBanner(network: network),
            ),
            Expanded(child: widget.child),
          ],
        );
      },
    );
  }
}

class _NetworkStatusBanner extends StatelessWidget {
  final NetworkService network;
  const _NetworkStatusBanner({required this.network});

  @override
  Widget build(BuildContext context) {
    if (network.quality == NetworkQuality.good) return const SizedBox.shrink();

    final isOffline = network.quality == NetworkQuality.offline;

    final bgColor = isOffline
        ? const Color(0xFF3b0a0a)
        : const Color(0xFF2d1f00);

    final borderColor = isOffline
        ? const Color(0xFFef4444)
        : const Color(0xFFf59e0b);

    final textColor = isOffline
        ? const Color(0xFFfca5a5)
        : const Color(0xFFfde68a);

    final icon = isOffline ? Icons.wifi_off_rounded : Icons.wifi_find_rounded;

    final message = isOffline
        ? 'You\'re offline — some content cannot be loaded'
        : 'Slow connection detected${network.latencyMs != null ? ' (${network.latencyMs}ms)' : ''} — things may take longer to load';

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: bgColor,
        border: Border(
          bottom: BorderSide(color: borderColor.withOpacity(0.4), width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
      child: Row(
        children: [
          Icon(icon, size: 15, color: textColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: textColor,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.1,
              ),
            ),
          ),
        ],
      ),
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