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

  /// Origin for public share pages (Next.js /share/[token]). If empty, falls back to API origin without /api.
  static String get _shareLinkBaseUrl {
    if (_isInitialized) {
      final envValue = dotenv.env['SHARE_LINK_BASE_URL'];
      if (envValue != null && envValue.isNotEmpty) {
        return envValue.replaceAll(RegExp(r'/+$'), '');
      }
    }
    return const String.fromEnvironment(
      'SHARE_LINK_BASE_URL',
      defaultValue: '',
    );
  }

  static String get _googleClientId {
    if (_isInitialized) {
      final envValue = dotenv.env['GOOGLE_CLIENT_ID'];
      if (envValue != null && envValue.isNotEmpty) {
        return envValue;
      }
    }
    return const String.fromEnvironment(
      'GOOGLE_CLIENT_ID',
      defaultValue: '',
    );
  }

  // API Configuration
  /// e.g. https://tripthread.app — must serve /share/[token] and host AASA / assetlinks for Universal Links.
  static String get shareLinkBaseUrl => _shareLinkBaseUrl;

  /// Resolved origin used in shared HTTPS links.
  static String get effectiveShareLinkOrigin {
    final custom = _shareLinkBaseUrl.trim();
    if (custom.isNotEmpty) return custom;
    final api = _baseUrl.replaceAll(RegExp(r'/+$'), '');
    return api.replaceAll(RegExp(r'/api$'), '');
  }

  /// Raw `CHAT_WS_BASE_URL` / `CHAT_WS_ORIGIN` from env or dart-define (trimmed), or empty.
  static String get _chatWsRawOverride {
    if (_isInitialized) {
      final v = dotenv.env['CHAT_WS_BASE_URL'] ?? dotenv.env['CHAT_WS_ORIGIN'];
      if (v != null && v.trim().isNotEmpty) return v.trim();
    }
    return const String.fromEnvironment(
      'CHAT_WS_BASE_URL',
      defaultValue: '',
    ).trim();
  }

  /// REST base URL aligned with the process that hosts WebSocket + [chatEventBus] (server.cjs).
  ///
  /// REST API and WebSocket both run on the same port via server.cjs (`npm run dev` defaults to :3000).
  /// Override via `CHAT_WS_BASE_URL` only when the WS host/port genuinely differs from the API host/port.
  static String get _resolvedApiBaseUrl {
    final apiUri = Uri.parse(_baseUrl);
    final raw = _chatWsRawOverride;
    if (raw.isNotEmpty) {
      final wsOrigin = Uri.parse(raw.contains('://') ? raw : 'http://$raw');
      if (wsOrigin.host.toLowerCase() == apiUri.host.toLowerCase() &&
          wsOrigin.hasPort &&
          apiUri.hasPort &&
          wsOrigin.port != apiUri.port) {
        if (kDebugMode) {
          debugPrint(
            '[AppConfig] API port ${apiUri.port} → ${wsOrigin.port} (same host as CHAT_WS_BASE_URL; REST must use chat server)',
          );
        }
        return apiUri.replace(port: wsOrigin.port).toString();
      }
    }
    return _baseUrl;
  }

  static String get apiBaseUrl {
    final resolved = _resolvedApiBaseUrl;
    if (kDebugMode) {
      debugPrint('[AppConfig] Using API base URL: $resolved');
      if (resolved != _baseUrl) {
        debugPrint('[AppConfig] (raw API_BASE_URL in .env was $_baseUrl)');
      }
    }
    return resolved;
  }

  /// HTTP(S) origin (no path) for the chat WebSocket; the client appends `/chat`.
  ///
  /// Matches [_resolvedApiBaseUrl] unless `CHAT_WS_BASE_URL` is set to a different host/port.
  static Uri get chatWebSocketHttpOrigin {
    final raw = _chatWsRawOverride;
    if (raw.isNotEmpty) {
      final parsed = Uri.parse(raw.contains('://') ? raw : 'http://$raw');
      return Uri(
        scheme: parsed.scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
      );
    }
    final api = Uri.parse(_resolvedApiBaseUrl);
    return Uri(
      scheme: api.scheme,
      host: api.host,
      port: api.hasPort ? api.port : null,
    );
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

  /// Web OAuth client ID (same as backend GOOGLE_CLIENT_ID). Used as serverClientId so id token can be verified by backend.
  static String get googleClientId {
    return _googleClientId;
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
      final apiUri = Uri.parse(apiBaseUrl);
      final wsUri = chatWebSocketHttpOrigin;
      final apiPort = apiUri.hasPort ? '${apiUri.port}' : '(default)';
      final wsPort = wsUri.hasPort ? '${wsUri.port}' : '(default)';
      if (apiUri.host != wsUri.host || apiUri.port != wsUri.port) {
        debugPrint(
          '[AppConfig] Chat WS origin ${wsUri.scheme}://${wsUri.host}:$wsPort '
          '≠ API ${apiUri.scheme}://${apiUri.host}:$apiPort (split dev or CHAT_WS_BASE_URL)',
        );
      } else {
        debugPrint(
          '[AppConfig] Chat WS: same origin as API (${wsUri.host}:$wsPort)',
        );
      }
      debugPrint('[AppConfig] Environment: $environment');
    }
  }
}
