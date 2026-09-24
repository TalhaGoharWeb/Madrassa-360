/// نیٹ ورک کی افادیت
/// Network and Connectivity Utilities

import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../utils/error_handler.dart';

class NetworkService {
  static final Connectivity _connectivity = Connectivity();
  static StreamController<bool>? _connectionStatusController;

  /// Initialize network monitoring
  static void init() {
    _connectionStatusController = StreamController<bool>.broadcast();
    _connectivity.onConnectivityChanged.listen((result) {
      _connectionStatusController?.add(result != ConnectivityResult.none);
    });
  }

  /// Get connection status stream
  static Stream<bool>? get connectionStatus => _connectionStatusController?.stream;

  /// Check if device is connected to internet
  static Future<bool> isConnected() async {
    try {
      final result = await _connectivity.checkConnectivity();
      return result != ConnectivityResult.none;
    } catch (e) {
      return false;
    }
  }

  /// Check internet connection with ping test
  static Future<bool> hasInternetConnection() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } on SocketException catch (_) {
      return false;
    } catch (e) {
      return false;
    }
  }

  /// Get connection type
  static Future<String> getConnectionType() async {
    final result = await _connectivity.checkConnectivity();
    switch (result) {
      case ConnectivityResult.wifi:
        return 'WiFi';
      case ConnectivityResult.mobile:
        return 'موبائل ڈیٹا';
      case ConnectivityResult.ethernet:
        return 'Ethernet';
      case ConnectivityResult.none:
        return 'منقطع';
      default:
        return 'نامعلوم';
    }
  }

  /// Throw exception if not connected
  static Future<void> requireConnection() async {
    final connected = await isConnected();
    if (!connected) {
      throw NetworkException('انٹرنیٹ کنیکشن دستیاب نہیں ہے');
    }
  }

  /// Dispose network monitoring
  static void dispose() {
    _connectionStatusController?.close();
    _connectionStatusController = null;
  }
}
