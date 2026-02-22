import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/widgets/engagement/engagement_action_bar.dart';
import 'package:tripthread/widgets/mention_text.dart';
import 'package:tripthread/widgets/sheets/comment_bottom_sheet.dart';
import 'package:tripthread/widgets/sheets/share_bottom_sheet.dart';

class PostDetailScreen extends StatefulWidget {
  final String entityType;
  final String entityId;
  final String? scrollToCommentId;

  const PostDetailScreen({
    super.key,
    required this.entityType,
    required this.entityId,
    this.scrollToCommentId,
  });

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  TripFinalPost? _post;
  bool _isLoading = true;
  String? _error;
  bool _commentSheetOpened = false;

  @override
  void initState() {
    super.initState();
    _loadPost();
  }

  Future<void> _loadPost() async {
    if (!mounted) return;

    // Guard: TRIP_THREAD_ENTRY is not a standalone post — redirect user
    if (widget.entityType == 'TRIP_THREAD_ENTRY') {
      setState(() {
        _error = 'Thread entries must be viewed from the trip thread.';
        _isLoading = false;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });
    final api = context.read<ApiService>();
    final response = await api.getPost(widget.entityType, widget.entityId);
    if (!mounted) return;
    if (response.success && response.data != null) {
      try {
        final post = TripFinalPost.fromJson(response.data!);
        context.read<EngagementProvider>().setLikeStatus(post.id, post.hasLiked);
        context.read<EngagementProvider>().setLikeCount(post.id, post.likeCount);
        setState(() {
          _post = post;
          _isLoading = false;
          _error = null;
        });
        if (widget.scrollToCommentId != null && !_commentSheetOpened) {
          _commentSheetOpened = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _openCommentSheet(widget.scrollToCommentId!);
          });
        }
      } catch (e, stackTrace) {
        debugPrint('[PostDetailScreen] Failed to parse post response: $e');
        debugPrint('[PostDetailScreen] Stack trace: $stackTrace');
        setState(() {
          _error = 'Failed to load post: ${e.toString().split('\n').first}';
          _isLoading = false;
        });
      }
    } else {
      debugPrint(
        '[PostDetailScreen] API returned error: ${response.error} '
        '(entityType=${widget.entityType}, entityId=${widget.entityId})',
      );
      setState(() {
        _error = response.error ?? 'Failed to load post';
        _isLoading = false;
      });
    }
  }

  void _openCommentSheet([String? scrollToCommentId]) {
    if (_post == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => CommentBottomSheet(
        entityType: 'TRIP_FINAL_POST',
        entityId: _post!.id,
        scrollToCommentId: scrollToCommentId,
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    if (difference.inDays > 0) return '${difference.inDays}d ago';
    if (difference.inHours > 0) return '${difference.inHours}h ago';
    if (difference.inMinutes > 0) return '${difference.inMinutes}m ago';
    return 'Just now';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Post'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadPost,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    if (_post == null) {
      return const Center(child: Text('Post not found'));
    }
    return SingleChildScrollView(
      child: _buildPostCard(context, _post!),
    );
  }

  Widget _buildPostCard(BuildContext context, TripFinalPost post) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: post.trip?.user?.avatarUrl != null
                      ? NetworkImage(post.trip!.user!.avatarUrl!)
                      : null,
                  child: post.trip?.user?.avatarUrl == null
                      ? Icon(Icons.person, color: Colors.white, size: 20)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        post.trip?.user?.name ??
                            post.trip?.user?.username ??
                            'Travel Story',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        _formatDateTime(post.createdAt),
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
              ],
            ),
          ),
          if (post.curatedMedia.isNotEmpty)
            SizedBox(
              height: 300,
              child: PageView.builder(
                itemCount: post.curatedMedia.length,
                itemBuilder: (context, index) {
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(
                            alpha: Theme.of(context).brightness == Brightness.dark
                                ? 0.06
                                : 0.03,
                          ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        buildOptimizedImageUrl(
                          post.curatedMedia[index],
                          width: 1600,
                        ),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Theme.of(context)
                                .colorScheme
                                .onSurface
                                .withValues(
                                  alpha:
                                      Theme.of(context).brightness ==
                                              Brightness.dark
                                          ? 0.06
                                          : 0.03,
                                ),
                            child: const Center(
                              child: Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: Colors.grey,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                MentionText(
                  text: post.summaryText,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (post.caption != null) ...[
                  const SizedBox(height: 8),
                  MentionText(
                    text: post.caption!,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant
                          .withValues(alpha: 0.9),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: EngagementActionBar(
                          entityType: 'TRIP_FINAL_POST',
                          entityId: post.id,
                          likeCount: post.likeCount,
                          commentCount: post.commentCount,
                          shareCount: post.shareCount,
                          hasLiked: post.hasLiked,
                          onCommentTap: () => _openCommentSheet(),
                          onShareTap: () {
                            showModalBottomSheet(
                              context: context,
                              backgroundColor: Colors.transparent,
                              builder: (context) => ShareBottomSheet(
                                entityType: 'TRIP_FINAL_POST',
                                entityId: post.id,
                              ),
                            );
                          },
                          onLikeChanged: () {
                            final engagementProvider =
                                context.read<EngagementProvider>();
                            final newLikeCount =
                                engagementProvider.getLikeCount(post.id);
                            final newHasLiked =
                                engagementProvider.isLiked(post.id);
                            setState(() {
                              _post = post.copyWith(
                                likeCount: newLikeCount,
                                hasLiked: newHasLiked,
                              );
                            });
                          },
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        context.push(
                          '/trip/${post.tripId}',
                          extra: {'from': '/post'},
                        );
                      },
                      child: const Text('View Trip'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
