import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/ui/widgets/like_button.dart';

class EngagementActionBar extends StatelessWidget {
  final String entityType;
  final String entityId;
  final int? likeCount;
  final int? commentCount;
  final int? shareCount;
  final bool? hasLiked;
  final VoidCallback? onCommentTap;
  final VoidCallback? onShareTap;
  final VoidCallback? onLikeChanged;

  const EngagementActionBar({
    super.key,
    required this.entityType,
    required this.entityId,
    this.likeCount,
    this.commentCount,
    this.shareCount,
    this.hasLiked,
    this.onCommentTap,
    this.onShareTap,
    this.onLikeChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<EngagementProvider>(
      builder: (context, provider, child) {
        final currentCommentCount = commentCount ?? 0;
        final currentShareCount = shareCount ?? 0;

        return Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.start,
          children: [
            LikeButton(
              entityType: entityType,
              entityId: entityId,
              initialLikeCount: likeCount,
              initialLiked: hasLiked,
              onLikeChanged: onLikeChanged,
            ),
            const SizedBox(width: 20),
            _ActionButton(
              icon: Icons.comment_outlined,
              count: currentCommentCount,
              onTap: () {
                HapticFeedback.lightImpact();
                onCommentTap?.call();
              },
            ),
            const SizedBox(width: 20),
            _ActionButton(
              icon: Icons.share_outlined,
              count: currentShareCount,
              onTap: () {
                HapticFeedback.lightImpact();
                onShareTap?.call();
              },
            ),
          ],
        );
      },
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final int count;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 24, color: Colors.grey),
          const SizedBox(width: 4),
          if (count > 0)
            Text(
              _formatCount(count),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.grey,
                    fontWeight: FontWeight.w500,
                  ),
            ),
        ],
      ),
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
}

