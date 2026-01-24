import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/share_provider.dart';

class ShareBottomSheet extends StatelessWidget {
  final String entityType;
  final String entityId;

  const ShareBottomSheet({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(
                alpha: isDark ? 0.20 : 0.14,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text('Share', style: theme.textTheme.titleLarge),
          const SizedBox(height: 24),
          Consumer<ShareProvider>(
            builder: (context, provider, child) {
              final isCreating = provider.isCreating('$entityType:$entityId');

              return Column(
                children: [
                  _ShareOption(
                    icon: Icons.share,
                    label: 'Share via...',
                    onTap: () async {
                      if (isCreating) return;
                      try {
                        final shareUrl = await provider.createShare(
                          entityType,
                          entityId,
                        );
                        // Open native share dialog
                        await provider.openNativeShare(
                          shareUrl,
                          text:
                              'Check out this amazing travel story on TripThread!',
                        );
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to share: ${e.toString()}'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    isLoading: isCreating,
                  ),
                  const SizedBox(height: 12),
                  _ShareOption(
                    icon: Icons.link,
                    label: 'Copy Link',
                    onTap: () async {
                      if (isCreating) return;
                      try {
                        final shareUrl = await provider.createShare(
                          entityType,
                          entityId,
                        );
                        await Clipboard.setData(ClipboardData(text: shareUrl));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Link copied to clipboard'),
                            ),
                          );
                          Navigator.of(context).pop();
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Failed to copy link: ${e.toString()}',
                              ),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    },
                    isLoading: isCreating,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _ShareOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isLoading;

  const _ShareOption({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    final tileBg = colorScheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.04);
    final tileBorder =
        colorScheme.onSurface.withValues(alpha: isDark ? 0.18 : 0.10);

    return InkWell(
      onTap: isLoading ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: tileBg,
          border: Border.all(color: tileBorder),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: colorScheme.onSurface),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
            ),
            if (isLoading)
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            else
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}
