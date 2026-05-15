import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/utils/user_display_labels.dart';
import 'package:tripthread/widgets/mention_text.dart';
import 'package:cached_network_image/cached_network_image.dart';

class CommentListItem extends StatefulWidget {
  final Comment comment;
  final bool isReply;
  final VoidCallback? onReplyTap;
  final VoidCallback? onViewReplies;
  final bool isExpanded;

  const CommentListItem({
    super.key,
    required this.comment,
    this.isReply = false,
    this.onReplyTap,
    this.onViewReplies,
    this.isExpanded = false,
  });

  @override
  State<CommentListItem> createState() => _CommentListItemState();
}

class _CommentListItemState extends State<CommentListItem> {
  bool _showFullText = false;
  bool _serverRejectedEditWindow = false;

  bool _withinAuthorEditWindow() {
    return DateTime.now().difference(widget.comment.createdAt) <=
        const Duration(minutes: 15);
  }

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isOwnComment = authProvider.currentUser?.id == widget.comment.userId;
    final text = widget.comment.contentText;
    final shouldTruncate = text.length > 150;
    final inEditWindow =
        isOwnComment && !_serverRejectedEditWindow && _withinAuthorEditWindow();

    return Dismissible(
      key: Key(widget.comment.id),
      direction: isOwnComment && inEditWindow
          ? DismissDirection.endToStart
          : DismissDirection.none,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        color: Colors.red,
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.endToStart && isOwnComment) {
          return await _showDeleteConfirmation();
        }
        return false;
      },
      onDismissed: (direction) {
        if (isOwnComment) {
          _deleteComment();
        }
      },
      child: Container(
        margin: EdgeInsets.only(left: widget.isReply ? 48 : 0, bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () {
                context.push('/profile/${widget.comment.userId}');
              },
              child: CircleAvatar(
                radius: 18,
                backgroundImage:
                    widget.comment.user?.avatarUrl != null &&
                        widget.comment.user!.avatarUrl!.isNotEmpty
                    ? CachedNetworkImageProvider(widget.comment.user!.avatarUrl!)
                    : null,
                child:
                    (widget.comment.user?.avatarUrl == null ||
                        widget.comment.user!.avatarUrl!.isEmpty)
                    ? Text(
                        userAvatarInitial(
                          username: widget.comment.user?.username,
                          name: widget.comment.user?.name,
                        ),
                        style: const TextStyle(fontSize: 14),
                      )
                    : null,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: () {
                            context.push('/profile/${widget.comment.userId}');
                          },
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.comment.user != null
                                    ? userPrimaryLabel(
                                        id: widget.comment.user!.id,
                                        username: widget.comment.user!.username,
                                        name: widget.comment.user!.name,
                                      )
                                    : userPrimaryLabel(
                                        id: widget.comment.userId,
                                        username: null,
                                        name: null,
                                      ),
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              if (widget.comment.user != null &&
                                  userSecondaryName(
                                        username: widget.comment.user!.username,
                                        name: widget.comment.user!.name,
                                      ) !=
                                      null)
                                Text(
                                  userSecondaryName(
                                    username: widget.comment.user!.username,
                                    name: widget.comment.user!.name,
                                  )!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                      ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatRelativeTime(widget.comment.createdAt),
                        style: Theme.of(
                          context,
                        ).textTheme.bodySmall?.copyWith(color: Colors.grey),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: GestureDetector(
                          onTap: shouldTruncate
                              ? () =>
                                    setState(() => _showFullText = !_showFullText)
                              : null,
                          child: MentionText(
                            text: _showFullText || !shouldTruncate
                                ? text
                                : '${text.substring(0, 150)}...',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      _CommentLikeButton(comment: widget.comment),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.start,
                      spacing: 0,
                      runSpacing: 4,
                      children: [
                        if (widget.comment.replyCount != null &&
                            widget.comment.replyCount! > 0 &&
                            widget.onViewReplies != null)
                          TextButton.icon(
                            onPressed: widget.onViewReplies,
                            icon: Icon(
                              widget.isExpanded
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                            ),
                            label: Text(
                              widget.isExpanded
                                  ? 'Hide replies'
                                  : 'View ${widget.comment.replyCount} ${widget.comment.replyCount == 1 ? 'reply' : 'replies'}',
                            ),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        if (widget.onReplyTap != null)
                          TextButton.icon(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              widget.onReplyTap!();
                            },
                            icon: const Icon(Icons.reply, size: 16),
                            label: const Text('Reply'),
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        if (isOwnComment && inEditWindow)
                          TextButton(
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              _editComment();
                            },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: Colors.grey[600],
                            ),
                            child: const Text(
                              'Edit',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                        if (isOwnComment && inEditWindow)
                          TextButton(
                            onPressed: () async {
                              HapticFeedback.lightImpact();
                              final confirmed =
                                  await _showDeleteConfirmation();
                              if (confirmed) {
                                _deleteComment();
                              }
                            },
                            style: TextButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              foregroundColor: Colors.grey[600],
                            ),
                            child: const Text(
                              'Delete',
                              style: TextStyle(fontSize: 13),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<bool> _showDeleteConfirmation() async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Delete Comment'),
            content: const Text(
              'Are you sure you want to delete this comment?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text(
                  'Delete',
                  style: TextStyle(color: Colors.red),
                ),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteComment() async {
    final commentId = widget.comment.id;
    final commentProvider = context.read<CommentProvider>();
    final engagementProvider = context.read<EngagementProvider>();
    // Capture reply IDs before delete (deleteComment removes them from provider).
    final replyIds = widget.isReply
        ? <String>[]
        : commentProvider
            .getRepliesList(commentId)
            .map((r) => r.id)
            .toList();

    try {
      await commentProvider.deleteComment(commentId);
      // Always clear engagement for the deleted comment (and its replies) so
      // sync and counts stay correct. Do this even if this widget is disposed,
      // so we don't leave stale state or affect the "below" comment's display.
      engagementProvider.clearEntity(commentId);
      for (final id in replyIds) {
        engagementProvider.clearEntity(id);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment deleted')),
        );
      }
    } catch (e) {
      if (e is ValidationException && mounted) {
        setState(() => _serverRejectedEditWindow = true);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ValidationException
                  ? 'Delete window expired for this comment.'
                  : 'Failed to delete comment: ${e.toString()}',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editComment() async {
    final textController = TextEditingController(
      text: widget.comment.contentText,
    );
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Comment'),
        content: TextField(
          controller: textController,
          maxLength: 250,
          maxLines: 4,
          decoration: const InputDecoration(hintText: 'Edit your comment...'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(textController.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      try {
        final provider = context.read<CommentProvider>();
        await provider.updateComment(widget.comment.id, result);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Comment updated')));
        }
      } catch (e) {
        if (e is ValidationException && mounted) {
          setState(() => _serverRejectedEditWindow = true);
        }
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                e is ValidationException
                    ? 'Edit window expired for this comment.'
                    : 'Failed to update comment: ${e.toString()}',
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  String _formatRelativeTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${dateTime.month}/${dateTime.day}';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m';
    } else {
      return 'now';
    }
  }
}

// Fixed visual size for liked vs unliked so reopening the sheet does not change scale.
const double _kCommentHeartIconSize = 22;

class _CommentLikeButton extends StatelessWidget {
  final Comment comment;

  const _CommentLikeButton({required this.comment});

  Future<void> _toggleLike(
    BuildContext context,
    EngagementProvider provider,
    bool wasLiked,
  ) async {
    HapticFeedback.lightImpact();
    try {
      await provider.toggleLike('COMMENT', comment.id);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to ${wasLiked ? 'unlike' : 'like'} comment'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<EngagementProvider>(
      builder: (context, provider, _) {
        final isLiked = provider.likeStatus.containsKey(comment.id)
            ? provider.isLiked(comment.id)
            : false;
        final likeCount = provider.likeCounts.containsKey(comment.id)
            ? provider.getLikeCount(comment.id)
            : comment.likeCount;
        final isToggling = provider.isToggling(comment.id);

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IconButton(
              onPressed: isToggling
                  ? null
                  : () => _toggleLike(context, provider, isLiked),
              icon: Icon(
                isLiked ? Icons.favorite : Icons.favorite_border,
                size: _kCommentHeartIconSize,
                color: isLiked ? Colors.red : Colors.grey,
              ),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 44, height: 44),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
            if (likeCount > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  likeCount.toString(),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isLiked ? Colors.red : Colors.grey,
                        fontWeight:
                            isLiked ? FontWeight.w600 : FontWeight.normal,
                      ),
                ),
              ),
          ],
        );
      },
    );
  }
}
