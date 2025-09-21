import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/foundation.dart';

class AppConfig {
  static const String _defaultBaseUrl = 'http://localhost:3000/api';

  // For debugging: set this to true to bypass dotenv and use hardcoded values
  static const bool _useHardcodedConfig = true;

  // Hardcoded configuration for debugging
  static const String _hardcodedBaseUrl = 'http://192.168.0.110:3000/api';

  // API Configuration
  static String get apiBaseUrl {
    // Use hardcoded config if enabled
    if (_useHardcodedConfig) {
      if (kDebugMode) {
        debugPrint(
            '[AppConfig] Using hardcoded API base URL: $_hardcodedBaseUrl');
      }
      return _hardcodedBaseUrl;
    }

    try {
      final url = dotenv.env['API_BASE_URL'] ?? _defaultBaseUrl;
      if (kDebugMode) {
        debugPrint('[AppConfig] Using API base URL: $url');
      }
      return url;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfig] Error getting API base URL, using default: $e');
      }
      return _defaultBaseUrl;
    }
  }

  // Environment
  static String get environment {
    // Use hardcoded config if enabled
    if (_useHardcodedConfig) {
      return 'development';
    }

    try {
      return dotenv.env['ENVIRONMENT'] ?? 'development';
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfig] Error getting environment, using default: $e');
      }
      return 'development';
    }
  }

  // Timeouts
  static const Duration connectTimeout = Duration(seconds: 30);
  static const Duration receiveTimeout = Duration(seconds: 30);

  // Headers
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
  };

  // API Endpoints (for easy access)
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

  // Initialize environment variables
  static Future<void> initialize() async {
    try {
      // Try to load the .env file from multiple possible locations
      bool loaded = false;

      // Try different possible paths
      final possiblePaths = [
        '.env',
        'assets/.env',
        '../.env',
      ];

      for (final path in possiblePaths) {
        try {
          await dotenv.load(fileName: path);
          loaded = true;
          if (kDebugMode) {
            debugPrint('[AppConfig] Successfully loaded .env from: $path');
          }
          break;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('[AppConfig] Failed to load from $path: $e');
          }
        }
      }

      if (loaded) {
        if (kDebugMode) {
          debugPrint(
              '[AppConfig] Environment configuration loaded successfully');
          debugPrint('[AppConfig] API Base URL: $apiBaseUrl');
          debugPrint('[AppConfig] Environment: $environment');
        }
      } else {
        if (kDebugMode) {
          debugPrint('[AppConfig] Could not load .env from any location');
          debugPrint('[AppConfig] Using default configuration');
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[AppConfig] Failed to load .env file: $e');
        debugPrint('[AppConfig] Using default configuration');
      }

      // Note: dotenv.env is read-only, so we can't set values on it
      // The app will use the fallback values defined in the getters
      if (kDebugMode) {
        debugPrint('[AppConfig] Will use fallback values from getters');
      }
    }
  }
}
