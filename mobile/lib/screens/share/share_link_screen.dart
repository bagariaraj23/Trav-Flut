import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/share_service.dart';
import 'package:tripthread/utils/error_handler.dart';

/// Resolves a share token from deep links and navigates to the target post.
class ShareLinkScreen extends StatefulWidget {
  const ShareLinkScreen({super.key, required this.shareToken});

  final String shareToken;

  @override
  State<ShareLinkScreen> createState() => _ShareLinkScreenState();
}

class _ShareLinkScreenState extends State<ShareLinkScreen> {
  String? _error;
  bool _suggestLogin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  String get _loginResumePath {
    final encoded = Uri.encodeComponent('/share/${widget.shareToken}');
    return '/login?from=$encoded';
  }

  Future<void> _resolve() async {
    setState(() {
      _error = null;
      _suggestLogin = false;
    });
    try {
      final entity =
          await context.read<ShareService>().resolveShare(widget.shareToken);
      if (!mounted) return;
      final type = entity.entityType;
      final id = entity.entityId;
      if (type == 'TRIP_FINAL_POST' && id.isNotEmpty) {
        context.go('/post/TRIP_FINAL_POST/$id');
        return;
      }
      setState(() => _error = 'This content type cannot be opened here yet.');
    } catch (e) {
      if (!mounted) return;
      final isLoggedIn = context.read<AuthProvider>().isAuthenticated;
      final message = e is AppException
          ? e.message
          : 'Link is invalid, expired, or you do not have access.';
      setState(() {
        _error = message;
        // Logged-out users can retry after signing in (private posts / canViewEntity).
        _suggestLogin = !isLoggedIn;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = context.watch<AuthProvider>().isAuthenticated;

    return Scaffold(
      appBar: AppBar(title: const Text('Opening…')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error == null
              ? const CircularProgressIndicator()
              : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.link_off,
                      size: 48,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    if (_suggestLogin && !isLoggedIn) ...[
                      FilledButton(
                        onPressed: () => context.go(_loginResumePath),
                        child: const Text('Log in'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (isLoggedIn)
                      FilledButton(
                        onPressed: () => context.go('/home'),
                        child: const Text('Go to home'),
                      )
                    else
                      TextButton(
                        onPressed: () => context.go('/login'),
                        child: const Text('Back to login'),
                      ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _resolve,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
