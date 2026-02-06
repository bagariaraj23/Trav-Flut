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

  void setRouter(GoRouter router) {
    _router = router;
  }

  Future<void> initialize() async {
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

      // Handle share links
      if (uri.path.startsWith('/share/')) {
        if (uri.pathSegments.isNotEmpty) {
          final shareToken = uri.pathSegments.last;
          if (shareToken.isNotEmpty) {
            debugPrint(
              '[DeepLinkService] Navigating to shared content: $shareToken',
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
  }
}
