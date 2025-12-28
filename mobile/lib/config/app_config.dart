import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class AppConfig {
  // Track if dotenv has been initialized
  static bool _isInitialized = false;
  
  // Read from .env file (loaded via flutter_dotenv) with fallback to dart-define or defaults
  static String get _baseUrl {
    // Priority: .env file > dart-define > default
    if (_isInitialized) {
      final envValue = dotenv.env['API_BASE_URL'];
      if (envValue != null && envValue.isNotEmpty) {
        return envValue;
      }
    }
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://tripthread-backend-production.up.railway.app/api',
    );
  }
  
  static String get _mapboxToken {
    if (_isInitialized) {
      final envValue = dotenv.env['MAPBOX_ACCESS_TOKEN'];
      if (envValue != null && envValue.isNotEmpty) {
        return envValue;
      }
    }
    return const String.fromEnvironment(
      'MAPBOX_ACCESS_TOKEN',
      defaultValue: '',
    );
  }
  
  static String get _environment {
    if (_isInitialized) {
      final envValue = dotenv.env['ENVIRONMENT'];
      if (envValue != null && envValue.isNotEmpty) {
        return envValue;
      }
    }
    return const String.fromEnvironment(
      'ENVIRONMENT',
      defaultValue: 'production',
    );
  }

  // API Configuration
  static String get apiBaseUrl {
    if (kDebugMode) {
      debugPrint('[AppConfig] Using API base URL: $_baseUrl');
    }
    return _baseUrl;
  }

  // Mapbox Configuration
  static String get mapboxAccessToken {
    if (kDebugMode) {
      debugPrint('[AppConfig] Using Mapbox token');
    }
    return _mapboxToken;
  }

  // Environment
  static String get environment {
    return _environment;
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

  // Initialize - loads .env file
  static Future<void> initialize() async {
    try {
      await dotenv.load(fileName: '.env');
      _isInitialized = true;
      if (kDebugMode) {
        debugPrint('[AppConfig] Loaded .env file successfully');
      }
    } catch (e) {
      _isInitialized = false;
      if (kDebugMode) {
        debugPrint('[AppConfig] Failed to load .env file: $e');
        debugPrint('[AppConfig] Using dart-define or default values');
      }
    }
    
    if (kDebugMode) {
      debugPrint('[AppConfig] Configuration initialized');
      debugPrint('[AppConfig] API Base URL: $apiBaseUrl');
      debugPrint('[AppConfig] Environment: $environment');
    }
  }
}
