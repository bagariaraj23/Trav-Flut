import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/comment.dart';
import 'package:tripthread/providers/comment_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/widgets/engagement/centered_scrollable.dart';
import 'package:tripthread/widgets/engagement/comment_composer.dart';
import 'package:tripthread/widgets/engagement/comment_list_item.dart';

class CommentBottomSheet extends StatefulWidget {
  final String entityType;
  final String entityId;
  final String? scrollToCommentId;

  const CommentBottomSheet({
    super.key,
    required this.entityType,
    required this.entityId,
    this.scrollToCommentId,
  });

  @override
  State<CommentBottomSheet> createState() => _CommentBottomSheetState();
}

class _CommentBottomSheetState extends State<CommentBottomSheet> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, bool> _expandedReplies = {};
  String? _currentParentCommentId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadComments();
      if (widget.scrollToCommentId != null) {
        _scrollToComment(widget.scrollToCommentId!);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent * 0.8) {
      _loadMoreComments();
    }
  }

  Future<void> _loadComments() async {
    final provider = context.read<CommentProvider>();
    await provider.getComments(
      widget.entityType,
      widget.entityId,
      refresh: true,
    );
    if (!mounted) return;
    await _syncCommentLikeCounts(
      provider,
      '${widget.entityType}:${widget.entityId}',
    );
  }

  Future<void> _loadMoreComments() async {
    final provider = context.read<CommentProvider>();
    final entityKey = '${widget.entityType}:${widget.entityId}';
    if (provider.hasMore(entityKey) && !provider.isLoading(entityKey)) {
      await provider.getComments(
        widget.entityType,
        widget.entityId,
        refresh: false,
      );
      if (!mounted) return;
      await _syncCommentLikeCounts(provider, entityKey);
    }
  }

  Future<void> _syncCommentLikeCounts(
    CommentProvider provider,
    String entityKey,
  ) async {
    final comments = provider.getCommentsList(entityKey);
    if (comments.isEmpty) return;
    final engagementProvider = context.read<EngagementProvider>();
    engagementProvider.syncLikeCounts({
      for (final c in comments) c.id: c.likeCount,
    });
    final hasLikedFromApi =
        comments.every((c) => c.liked != null);
    if (hasLikedFromApi) {
      engagementProvider.setLikeStatusBatch({
        for (final c in comments) c.id: c.liked!,
      });
      return;
    }
    await engagementProvider.checkLikeStatus(
      comments.map((c) => c.id).toList(),
      'COMMENT',
    );
  }

  void _scrollToComment(String commentId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<CommentProvider>();
      final entityKey = '${widget.entityType}:${widget.entityId}';
      final comments = provider.getCommentsList(entityKey);
      final index = comments.indexWhere((c) => c.id == commentId);
      if (index >= 0 && _scrollController.hasClients) {
        final itemHeight = 100.0;
        _scrollController.animateTo(
          index * itemHeight,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _toggleReplies(String commentId) async {
    setState(() {
      _expandedReplies[commentId] = !(_expandedReplies[commentId] ?? false);
    });
    if (_expandedReplies[commentId] == true) {
      final provider = context.read<CommentProvider>();
      await provider.getReplies(commentId);
      if (!mounted) return;
      await _syncReplyLikeCounts(provider, commentId);
    }
  }

  Future<void> _syncReplyLikeCounts(
    CommentProvider provider,
    String parentCommentId,
  ) async {
    final replies = provider.getRepliesList(parentCommentId);
    if (replies.isEmpty) return;
    final engagementProvider = context.read<EngagementProvider>();
    engagementProvider.syncLikeCounts({
      for (final r in replies) r.id: r.likeCount,
    });
    final hasLikedFromApi = replies.every((r) => r.liked != null);
    if (hasLikedFromApi) {
      engagementProvider.setLikeStatusBatch({
        for (final r in replies) r.id: r.liked!,
      });
      return;
    }
    await engagementProvider.checkLikeStatus(
      replies.map((r) => r.id).toList(),
      'COMMENT',
    );
  }

  void _startReply(String commentId) {
    setState(() {
      _currentParentCommentId = commentId;
    });
  }

  void _cancelReply() {
    setState(() {
      _currentParentCommentId = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        final theme = Theme.of(context);
        final colorScheme = theme.colorScheme;
        final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
        final isDark = theme.brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: SafeArea(
            top: false,
            // Avoid extra bottom safe-area padding when keyboard is open.
            // This prevents small bottom overflows (e.g. ~29px) in the sheet.
            bottom: !isKeyboardOpen,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 12),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withValues(
                          alpha: isDark ? 0.20 : 0.14,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Text(
                            'Comments',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          const Spacer(),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.of(context).pop(),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Consumer<CommentProvider>(
                        builder: (context, provider, child) {
                          final entityKey =
                              '${widget.entityType}:${widget.entityId}';
                          final comments = provider.getCommentsList(entityKey);
                          final isLoading = provider.isLoading(entityKey);
                          final error = provider.error;

                          if (isLoading && comments.isEmpty) {
                            return const Center(child: CircularProgressIndicator());
                          }

                          if (error != null && comments.isEmpty) {
                            return CenteredScrollable(
                              controller: scrollController,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(error),
                                  const SizedBox(height: 16),
                                  ElevatedButton(
                                    onPressed: _loadComments,
                                    child: const Text('Retry'),
                                  ),
                                ],
                              ),
                            );
                          }

                          if (comments.isEmpty) {
                            return CenteredScrollable(
                              controller: scrollController,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.comment_outlined,
                                    size: 64,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No comments yet',
                                    style: Theme.of(context).textTheme.titleMedium,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Be the first to comment!',
                                    style: Theme.of(context).textTheme.bodyMedium,
                                  ),
                                ],
                              ),
                            );
                          }

                          return RefreshIndicator(
                            onRefresh: _loadComments,
                            child: ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              itemCount: comments.length + (isLoading ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == comments.length) {
                                  return const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator()),
                                  );
                                }

                                final comment = comments[index];
                                final isExpanded = _expandedReplies[comment.id] ?? false;
                                final replies = provider.getRepliesList(comment.id);
                                final hasReplies = comment.replyCount != null && comment.replyCount! > 0;

                                return Column(
                                  key: ValueKey(comment.id),
                                  children: [
                                    CommentListItem(
                                      comment: comment,
                                      isExpanded: isExpanded,
                                      onReplyTap: () => _startReply(comment.id),
                                      onViewReplies: hasReplies
                                          ? () => _toggleReplies(comment.id)
                                          : null,
                                    ),
                                    if (isExpanded && replies.isNotEmpty)
                                      ...replies.map(
                                        (reply) => CommentListItem(
                                          comment: reply,
                                          isReply: true,
                                          onReplyTap: () => _startReply(reply.id),
                                        ),
                                      ),
                                    if (isExpanded && replies.isEmpty && provider.isLoadingReplies(comment.id))
                                      const Padding(
                                        padding: EdgeInsets.only(left: 48, bottom: 8),
                                        child: CircularProgressIndicator(),
                                      ),
                                  ],
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    CommentComposer(
                      entityType: widget.entityType,
                      entityId: widget.entityId,
                      parentCommentId: _currentParentCommentId,
                      parentComment: _currentParentCommentId != null
                          ? _findComment(_currentParentCommentId!)
                          : null,
                      onCommentPosted: () {
                        _cancelReply();
                        _loadComments();
                      },
                      onCancel: _cancelReply,
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Comment? _findComment(String commentId) {
    final provider = context.read<CommentProvider>();
    final entityKey = '${widget.entityType}:${widget.entityId}';
    final comments = provider.getCommentsList(entityKey);
    try {
      return comments.firstWhere((c) => c.id == commentId);
    } catch (e) {
      for (final comment in comments) {
        final replies = provider.getRepliesList(comment.id);
        try {
          return replies.firstWhere((r) => r.id == commentId);
        } catch (_) {
          continue;
        }
      }
      return null;
    }
  }
}

