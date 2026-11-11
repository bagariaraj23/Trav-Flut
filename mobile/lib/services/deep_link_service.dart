import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:app_links/app_links.dart';
import 'package:go_router/go_router.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  StreamSubscription? _subscription;
  GoRouter? _router;
  final AppLinks _appLinks = AppLinks();
  bool _initialized = false;

  void setRouter(GoRouter router) {
    _router = router;
  }

  /// Idempotent: safe to call once after the router is ready.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;
    try {
      // Handle initial link if app was launched from a link
      final initialLink = await _appLinks.getInitialLink();
      if (initialLink != null) {
        debugPrint('[DeepLinkService] Initial link: $initialLink');
        _handleLink(initialLink.toString());
      }

      // Listen to incoming links
      _subscription = _appLinks.uriLinkStream.listen(
        (Uri? uri) {
          if (uri != null) {
            debugPrint('[DeepLinkService] Incoming link: $uri');
            _handleLink(uri.toString());
          }
        },
        onError: (err) {
          debugPrint('[DeepLinkService] Error handling deep link: $err');
        },
      );
    } catch (e) {
      _initialized = false;
      debugPrint('[DeepLinkService] Error initializing deep links: $e');
    }
  }

  void _handleLink(String link) {
    if (_router == null) {
      debugPrint('[DeepLinkService] Router not set, cannot handle link: $link');
      return;
    }

    try {
      final uri = Uri.parse(link);

      // Custom scheme: tripthread://share/{token}
      if (uri.scheme == 'tripthread') {
        if (uri.host == 'share') {
          final seg = uri.pathSegments.where((s) => s.isNotEmpty).toList();
          final token = seg.isNotEmpty ? seg.first : null;
          if (token != null && token.isNotEmpty) {
            debugPrint(
              '[DeepLinkService] App scheme share link, token: $token',
            );
            _router!.go('/share/$token');
            return;
          }
        }
      }

      // Handle password reset links
      if (uri.path.contains('reset') || uri.queryParameters.containsKey('t')) {
        final token = uri.queryParameters['t'];
        if (token != null) {
          debugPrint(
            '[DeepLinkService] Navigating to reset password with token',
          );
          _router!.go('/reset-password?t=$token');
        } else {
          debugPrint(
            '[DeepLinkService] Reset link without token, navigating to forgot password',
          );
          _router!.go('/forgot-password');
        }
        return;
      }

      // HTTPS (Universal / App Links): https://host/share/{token}
      if (uri.path.startsWith('/share/')) {
        final segments =
            uri.pathSegments.where((s) => s.isNotEmpty).toList();
        final shareIdx = segments.indexOf('share');
        if (shareIdx >= 0 && shareIdx + 1 < segments.length) {
          final shareToken = segments[shareIdx + 1];
          if (shareToken.isNotEmpty) {
            debugPrint(
              '[DeepLinkService] HTTPS share path, token: $shareToken',
            );
            _router!.go('/share/$shareToken');
            return;
          }
        }
      }

      // Handle other deep links here
      debugPrint('[DeepLinkService] Unhandled deep link: $link');
    } catch (e) {
      debugPrint('[DeepLinkService] Error parsing link: $e');
    }
  }

  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    _initialized = false;
  }
}
