import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
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

  @override
  Widget build(BuildContext context) {
    final authProvider = context.watch<AuthProvider>();
    final isOwnComment = authProvider.currentUser?.id == widget.comment.userId;
    final text = widget.comment.contentText;
    final shouldTruncate = text.length > 150;

    return Dismissible(
      key: Key(widget.comment.id),
      direction: isOwnComment
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
        margin: EdgeInsets.only(
          left: widget.isReply ? 48 : 0,
          bottom: 8,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 18,
              backgroundImage: widget.comment.user?.avatarUrl != null &&
                      widget.comment.user!.avatarUrl!.isNotEmpty
                  ? CachedNetworkImageProvider(widget.comment.user!.avatarUrl!)
                  : null,
              child: (widget.comment.user?.avatarUrl == null ||
                      widget.comment.user!.avatarUrl!.isEmpty)
                  ? Text(
                      (widget.comment.user?.name?.isNotEmpty == true
                              ? widget.comment.user!.name!.substring(0, 1)
                              : widget.comment.user?.username?.isNotEmpty == true
                                  ? widget.comment.user!.username!.substring(0, 1)
                                  : 'U')
                          .toUpperCase(),
                      style: const TextStyle(fontSize: 14),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        widget.comment.user?.name ?? 
                        widget.comment.user?.username ?? 
                        'Unknown',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatRelativeTime(widget.comment.createdAt),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      if (isOwnComment) ...[
                        const SizedBox(width: 8),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 16),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _editComment();
                            } else if (value == 'delete') {
                              _deleteComment();
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Icons.edit, size: 18),
                                  SizedBox(width: 8),
                                  Text('Edit'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Icons.delete, size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('Delete', style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: shouldTruncate
                        ? () => setState(() => _showFullText = !_showFullText)
                        : null,
                    child: Text(
                      _showFullText || !shouldTruncate
                          ? text
                          : '${text.substring(0, 150)}...',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      if (widget.comment.replyCount != null &&
                          widget.comment.replyCount! > 0 &&
                          widget.onViewReplies != null)
                        TextButton.icon(
                          onPressed: widget.onViewReplies,
                          icon: Icon(
                            widget.isExpanded ? Icons.expand_less : Icons.expand_more,
                            size: 16,
                          ),
                          label: Text(
                            widget.isExpanded
                                ? 'Hide replies'
                                : 'View ${widget.comment.replyCount} ${widget.comment.replyCount == 1 ? 'reply' : 'replies'}',
                          ),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      if (widget.comment.parentCommentId == null)
                        TextButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            widget.onReplyTap?.call();
                          },
                          icon: const Icon(Icons.reply, size: 16),
                          label: const Text('Reply'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                    ],
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
            content: const Text('Are you sure you want to delete this comment?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Delete', style: TextStyle(color: Colors.red)),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteComment() async {
    try {
      final provider = context.read<CommentProvider>();
      await provider.deleteComment(widget.comment.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comment deleted')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to delete comment: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _editComment() async {
    final textController = TextEditingController(text: widget.comment.contentText);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Comment'),
        content: TextField(
          controller: textController,
          maxLength: 250,
          maxLines: 4,
          decoration: const InputDecoration(
            hintText: 'Edit your comment...',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(textController.text.trim()),
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
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Comment updated')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to update comment: ${e.toString()}'),
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

