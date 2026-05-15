import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/services/share_service.dart';

/// Resolves a share token from deep links and navigates to the target post.
class ShareLinkScreen extends StatefulWidget {
  const ShareLinkScreen({super.key, required this.shareToken});

  final String shareToken;

  @override
  State<ShareLinkScreen> createState() => _ShareLinkScreenState();
}

class _ShareLinkScreenState extends State<ShareLinkScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _resolve());
  }

  Future<void> _resolve() async {
    try {
      final entity =
          await context.read<ShareService>().resolveShare(widget.shareToken);
      if (!mounted) return;
      final type = entity.entityType;
      final id = entity.entityId;
      if (type == 'TRIP_FINAL_POST') {
        context.go('/post/TRIP_FINAL_POST/$id');
        return;
      }
      setState(() => _error = 'This content type cannot be opened here yet.');
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Link is invalid, expired, or you do not have access.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
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
                    Icon(Icons.link_off, size: 48, color: Theme.of(context).colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => context.go('/home'),
                      child: const Text('Go to home'),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}
