import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/engagement_provider.dart';

class LikeButton extends StatefulWidget {
  final String entityType;
  final String entityId;
  final int? initialLikeCount;
  final bool? initialLiked;
  final VoidCallback? onLikeChanged;

  const LikeButton({
    super.key,
    required this.entityType,
    required this.entityId,
    this.initialLikeCount,
    this.initialLiked,
    this.onLikeChanged,
  });

  @override
  State<LikeButton> createState() => _LikeButtonState();
}

class _LikeButtonState extends State<LikeButton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Color?> _colorAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
      lowerBound: 0.0,
      upperBound: 1.0,
    );

    _colorAnimation = ColorTween(
      begin: Colors.grey,
      end: Colors.red,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Initialize animation state based on current like status
    final provider = context.read<EngagementProvider>();
    final isLiked = provider.likeStatus.containsKey(widget.entityId)
        ? provider.isLiked(widget.entityId)
        : (widget.initialLiked ?? false);

    if (isLiked && _controller.value != 1.0) {
      _controller.value = 1.0;
    } else if (!isLiked && _controller.value != 0.0) {
      _controller.value = 0.0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleTap() async {
    HapticFeedback.lightImpact();
    final provider = context.read<EngagementProvider>();
    final wasLiked = provider.isLiked(widget.entityId);

    // Animate based on action
    if (!wasLiked) {
      _controller.forward();
    } else {
      _controller.reverse();
    }

    try {
      await provider.toggleLike(widget.entityType, widget.entityId);
      // Update animation state after toggle
      final newLiked = provider.isLiked(widget.entityId);
      if (newLiked && _controller.value != 1.0) {
        _controller.animateTo(1.0);
      } else if (!newLiked && _controller.value != 0.0) {
        _controller.animateTo(0.0);
      }
      widget.onLikeChanged?.call();
    } catch (e) {
      // Rollback animation on error
      if (wasLiked) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to ${wasLiked ? 'unlike' : 'like'}: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EngagementProvider>(
      builder: (context, provider, child) {
        // Use provider state if available, otherwise fall back to initial values
        final providerLiked = provider.isLiked(widget.entityId);
        final providerCount = provider.getLikeCount(widget.entityId);
        final isLiked = provider.likeStatus.containsKey(widget.entityId)
            ? providerLiked
            : (widget.initialLiked ?? false);
        final likeCount = provider.likeCounts.containsKey(widget.entityId)
            ? providerCount
            : (widget.initialLikeCount ?? 0);
        final isToggling = provider.isToggling(widget.entityId);

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: isToggling ? null : _handleTap,
              borderRadius: BorderRadius.circular(24),
              child: Padding(
                padding: const EdgeInsets.all(
                  12.0,
                ), // Creates 48x48 touch target
                child: AnimatedBuilder(
                  animation: _controller,
                  builder: (context, child) {
                    // Clamp animation value to prevent errors
                    final animationValue = _controller.value.clamp(0.0, 1.0);
                    final scale = isLiked ? 1.0 + (animationValue * 0.2) : 1.0;

                    return Transform.scale(
                      scale: scale,
                      child: Icon(
                        isLiked ? Icons.favorite : Icons.favorite_border,
                        color: isLiked
                            ? (_colorAnimation.value ?? Colors.red)
                            : Colors.grey,
                        size: 24,
                      ),
                    );
                  },
                ),
              ),
            ),
            if (likeCount > 0)
              InkWell(
                onTap: () {
                  context.push(
                    '/likes/${widget.entityType}/${widget.entityId}',
                  );
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical:
                        12, // Increased vertical padding for better touch target
                  ),
                  child: Text(
                    _formatCount(likeCount),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: isLiked ? Colors.red : Colors.grey,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            if (isToggling)
              const Padding(
                padding: EdgeInsets.only(left: 8),
                child: SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
          ],
        );
      },
    );
  }

  String _formatCount(int count) {
    if (count < 1000) return count.toString();
    if (count < 1000000) return '${(count / 1000).toStringAsFixed(1)}K';
    return '${(count / 1000000).toStringAsFixed(1)}M';
  }
}
