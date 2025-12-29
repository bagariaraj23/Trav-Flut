import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';

class ConnectivityService extends ChangeNotifier {
  static final ConnectivityService _instance = ConnectivityService._internal();
  factory ConnectivityService() => _instance;
  ConnectivityService._internal();

  final Connectivity _connectivity = Connectivity();
  late StreamSubscription<List<ConnectivityResult>> _connectivitySubscription;

  ConnectivityResult _connectionStatus = ConnectivityResult.none;
  bool get isConnected => _connectionStatus != ConnectivityResult.none;
  bool get isWifi => _connectionStatus == ConnectivityResult.wifi;
  bool get isMobile => _connectionStatus == ConnectivityResult.mobile;

  ConnectivityResult get connectionStatus => _connectionStatus;

  Future<void> initialize() async {
    try {
      final results = await _connectivity.checkConnectivity();
      _connectionStatus = results.isNotEmpty
          ? results.first
          : ConnectivityResult.none;
      _connectivitySubscription = _connectivity.onConnectivityChanged.listen(
        (results) {
          _updateConnectionStatus(
            results.isNotEmpty ? results.first : ConnectivityResult.none,
          );
        },
        onError: (error) {
          debugPrint('Connectivity error: $error');
        },
      );
    } catch (e) {
      debugPrint('Failed to initialize connectivity service: $e');
    }
  }

  void _updateConnectionStatus(ConnectivityResult result) {
    _connectionStatus = result;
    notifyListeners();

    if (kDebugMode) {
      debugPrint('Connectivity changed: $result');
    }
  }

  Future<bool> hasInternetConnection() async {
    try {
      final List<ConnectivityResult> result = await _connectivity
          .checkConnectivity();
      return result.isNotEmpty && !result.contains(ConnectivityResult.none);
    } catch (e) {
      debugPrint('Error checking internet connection: $e');
      return false;
    }
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }
}
