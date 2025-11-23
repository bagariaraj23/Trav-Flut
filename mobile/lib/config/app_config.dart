import 'package:flutter/foundation.dart';

class AppConfig {
  // Read from --dart-define (works in release builds)
  static const String _dartDefineBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://tripthread-backend-production.up.railway.app/api',
  );
  
  static const String _dartDefineMapboxToken = String.fromEnvironment(
    'MAPBOX_ACCESS_TOKEN',
    defaultValue: '',
  );
  
  static const String _dartDefineEnvironment = String.fromEnvironment(
    'ENVIRONMENT',
    defaultValue: 'production',
  );

  // API Configuration
  static String get apiBaseUrl {
    if (kDebugMode) {
      debugPrint('[AppConfig] Using API base URL: $_dartDefineBaseUrl');
    }
    return _dartDefineBaseUrl;
  }

  // Mapbox Configuration
  static String get mapboxAccessToken {
    if (kDebugMode) {
      debugPrint('[AppConfig] Using Mapbox token');
    }
    return _dartDefineMapboxToken;
  }

  // Environment
  static String get environment {
    return _dartDefineEnvironment;
  }

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Headers
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
  };

  // API Endpoints
  static const String authEndpoint = '/auth';
  static const String usersEndpoint = '/users';
  static const String tripsEndpoint = '/trips';
  static const String feedEndpoint = '/feed';
  static const String discoverEndpoint = '/discover';
  static const String followEndpoint = '/follow';

  // Validation
  static bool get isValid {
    try {
      final url = Uri.parse(apiBaseUrl);
      return url.hasScheme && url.hasAuthority;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfig] Invalid API base URL: $apiBaseUrl');
      }
      return false;
    }
  }

  // Initialize - now a no-op since we use dart-define
  static Future<void> initialize() async {
    if (kDebugMode) {
      debugPrint('[AppConfig] Configuration initialized');
      debugPrint('[AppConfig] API Base URL: $apiBaseUrl');
      debugPrint('[AppConfig] Environment: $environment');
    }
  }
}
