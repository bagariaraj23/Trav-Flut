import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:go_router/go_router.dart';

class AuthGate extends StatelessWidget {
  final Widget child;
  const AuthGate({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    GoRouter? router;
    try {
      router = GoRouter.of(context);
    } catch (_) {
      // Router not found yet (e.g., splash root/etc). Don't crash.
      return child;
    }
    final location = router.routerDelegate.currentConfiguration.uri.toString();

    if (!auth.isAuthenticated &&
        !auth.isLoading &&
        location != '/login' &&
        location != '/signup' &&
        location != '/forgot-password' &&
        !location.startsWith('/reset-password')) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final redirectLoc =
            router?.routerDelegate.currentConfiguration.uri.toString();
        if (redirectLoc != '/login') {
          router?.go('/login');
        }
      });
      return const SizedBox.shrink();
    }
    return child;
  }
}
