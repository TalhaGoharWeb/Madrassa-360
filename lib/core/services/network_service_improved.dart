import 'package:flutter/material.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../constants/app_typography.dart';
import '../utils/error_handler.dart';

/// نیٹ ورک کی خدمت
/// Network Service for Connectivity Monitoring

class NetworkService {
  static final Connectivity _connectivity = Connectivity();

  /// Check if device is connected to internet
  static Future<bool> isConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      ErrorHandler.logError(e, null);
      return false;
    }
  }

  /// Get current connectivity status
  static Future<ConnectivityResult> getConnectivityStatus() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result;
    } catch (e) {
      ErrorHandler.logError(e, null);
      return ConnectivityResult.none;
    }
  }

  /// Stream of connectivity changes
  static Stream<ConnectivityResult> get onConnectivityChanged {
    return _connectivity.onConnectivityChanged;
  }

  /// Check connectivity and show dialog if offline
  static Future<bool> checkConnectivityWithDialog(BuildContext context) async {
    final isOnline = await isConnected();

    if (!isOnline && context.mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('انٹرنیٹ دستیاب نہیں'),
          content: const Text('براہ کرم اپنا انٹرنیٹ کنیکشن چیک کریں'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('ٹھیک ہے'),
            ),
          ],
        ),
      );
    }

    return isOnline;
  }

  /// Get connection type (WiFi, Mobile, etc.)
  static Future<String> getConnectionType() async {
    try {
      final result = await _connectivity.checkConnectivity();
      switch (result) {
        case ConnectivityResult.wifi:
          return 'WiFi';
        case ConnectivityResult.mobile:
          return 'موبائل ڈیٹا';
        case ConnectivityResult.ethernet:
          return 'Ethernet';
        case ConnectivityResult.vpn:
          return 'VPN';
        case ConnectivityResult.bluetooth:
          return 'Bluetooth';
        case ConnectivityResult.other:
          return 'دیگر';
        case ConnectivityResult.none:
          return 'غیر منسلک';
      }
    } catch (e) {
      ErrorHandler.logError(e, null);
      return 'نامعلوم';
    }
  }

  /// Retry an operation with connectivity check
  static Future<T?> retryWithConnectivity<T>({
    required Future<T> Function() operation,
    int maxRetries = 3,
    Duration retryDelay = const Duration(seconds: 2),
  }) async {
    int attempts = 0;

    while (attempts < maxRetries) {
      try {
        final isOnline = await isConnected();
        if (!isOnline) {
          throw NetworkException(userMessageUr: 'انٹرنیٹ دستیاب نہیں');
        }

        return await operation();
      } catch (e) {
        attempts++;
        if (attempts >= maxRetries) {
          throw NetworkException(userMessageUr: 'کنیکشن ناکام: $e');
        }
        await Future.delayed(retryDelay);
      }
    }

    return null;
  }
}

/// Network Status Widget
class NetworkStatusWidget extends StatelessWidget {
  final Widget child;

  const NetworkStatusWidget({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<ConnectivityResult>(
      stream: NetworkService.onConnectivityChanged,
      builder: (context, snapshot) {
        if (snapshot.hasData && snapshot.data == ConnectivityResult.none) {
          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                color: Colors.red,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.signal_wifi_off, color: Colors.white, size: 16),
                    SizedBox(width: 8),
                    Text(
                      'انٹرنیٹ دستیاب نہیں',
                      style: AppTypography.bodyMedium.copyWith(
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(child: child),
            ],
          );
        }
        return child;
      },
    );
  }
}
