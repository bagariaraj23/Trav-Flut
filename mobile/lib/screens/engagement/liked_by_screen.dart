import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/models/user.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/utils/app_feedback.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';

class LikedByScreen extends StatefulWidget {
  final String entityType;
  final String entityId;

  const LikedByScreen({
    super.key,
    required this.entityType,
    required this.entityId,
  });

  @override
  State<LikedByScreen> createState() => _LikedByScreenState();
}

class _LikedByScreenState extends State<LikedByScreen> {
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  bool _isLoadingMore = false;
  String? _followTogglingUserId;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadUsers();
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
      _loadMoreUsers();
    }
  }

  Future<void> _loadUsers() async {
    final provider = context.read<EngagementProvider>();
    await provider.getLikeUsers(widget.entityType, widget.entityId, 1);
    if (!mounted) return;
    await _fetchFollowStatusForUsers();
  }

  Future<void> _loadMoreUsers() async {
    if (_isLoadingMore) return;
    setState(() => _isLoadingMore = true);
    _currentPage++;
    try {
      final provider = context.read<EngagementProvider>();
      await provider.getLikeUsers(widget.entityType, widget.entityId, _currentPage);
      if (!mounted) return;
      await _fetchFollowStatusForUsers();
    } finally {
      if (mounted) {
        setState(() => _isLoadingMore = false);
      }
    }
  }

  Future<void> _fetchFollowStatusForUsers() async {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    if (currentUserId == null) return;

    final engagementProvider = context.read<EngagementProvider>();
    final cacheKey = '${widget.entityType}:${widget.entityId}';
    final users = engagementProvider.getLikeUsersList(cacheKey);
    final userProvider = context.read<UserProvider>();

    await Future.wait(
      users.where((u) => u.id != currentUserId).map((u) => userProvider.fetchDetailedFollowStatus(u.id)),
    );
  }

  Future<void> _handleFollowToggle(String userId) async {
    final userProvider = context.read<UserProvider>();
    final authProvider = context.read<AuthProvider>();

    if (authProvider.currentUser == null) return;

    setState(() => _followTogglingUserId = userId);

    await userProvider.fetchDetailedFollowStatus(userId);
    final detailedStatus = userProvider.getDetailedFollowStatus(userId);

    if (!mounted) return;

    if (detailedStatus == null) {
      setState(() => _followTogglingUserId = null);
      AppFeedback.showError(context, 'Unable to determine follow status');
      return;
    }

    bool success = false;
    String actionMessage = '';

    if (detailedStatus.isFollowing) {
      success = await userProvider.unfollowUser(
        userId,
        currentUserId: authProvider.currentUser!.id,
      );
      actionMessage = success
          ? (userProvider.error == null ? 'Successfully unfollowed user' : userProvider.error!)
          : (userProvider.error ?? 'Failed to unfollow user');
    } else if (detailedStatus.isRequestPending) {
      success = await userProvider.cancelFollowRequest(
        userId,
        currentUserId: authProvider.currentUser!.id,
      );
      actionMessage = success
          ? 'Follow request cancelled'
          : (userProvider.error ?? 'Failed to cancel follow request');
    } else {
      success = await userProvider.sendFollowRequest(
        userId,
        currentUserId: authProvider.currentUser!.id,
      );
      await userProvider.fetchDetailedFollowStatus(userId);
      final updatedStatus = userProvider.getDetailedFollowStatus(userId);
      if (success) {
        if (updatedStatus?.isFollowing == true) {
          actionMessage = 'Successfully following user';
        } else if (updatedStatus?.isRequestPending == true) {
          actionMessage = 'Follow request sent';
        } else {
          actionMessage = 'Follow request sent';
        }
      } else {
        actionMessage = userProvider.followRequestsError ??
            userProvider.error ??
            'Failed to send follow request';
      }
    }

    if (!mounted) return;

    setState(() => _followTogglingUserId = null);

    final errorMessage =
        userProvider.error ?? userProvider.followRequestsError ?? 'An error occurred';
    if (success) {
      AppFeedback.showSuccess(context, actionMessage);
    } else {
      AppFeedback.showError(context, errorMessage);
    }
  }

  Widget? _buildFollowButton(BuildContext context, User user) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    if (currentUserId == null || user.id == currentUserId) {
      return null;
    }

    final userProvider = context.read<UserProvider>();
    final status = userProvider.getDetailedFollowStatus(user.id);
    final isToggling = _followTogglingUserId == user.id;

    String label;
    if (status?.isFollowing == true) {
      label = 'Following';
    } else if (status?.isRequestPending == true) {
      label = 'Requested';
    } else {
      label = 'Follow';
    }

    return OutlinedButton(
      onPressed: isToggling ? null : () => _handleFollowToggle(user.id),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: const Size(0, 32),
      ),
      child: isToggling
          ? const SizedBox(
              height: 14,
              width: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Liked by'),
      ),
      body: AppLayout.reading(
        context: context,
        child: Consumer2<EngagementProvider, UserProvider>(
        builder: (context, engagementProvider, userProvider, child) {
          final users = engagementProvider.getLikeUsersList('${widget.entityType}:${widget.entityId}');
          final isLoading = engagementProvider.isLoadingUsers('${widget.entityType}:${widget.entityId}');
          final error = engagementProvider.error;

          if (isLoading && users.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (error != null && users.isEmpty) {
            return AppFeedback.error(
              context: context,
              title: 'Could not load likes',
              message: error,
              onRetry: _loadUsers,
            );
          }

          if (users.isEmpty) {
            return AppFeedback.empty(
              context: context,
              icon: Icons.favorite_border,
              title: 'No likes yet',
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              _currentPage = 1;
              await _loadUsers();
            },
            child: ListView.builder(
              controller: _scrollController,
              itemCount: users.length + (_isLoadingMore ? 1 : 0),
              itemBuilder: (context, index) {
                if (index == users.length) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                final user = users[index];
                if (user.id.isEmpty) {
                  return const SizedBox.shrink();
                }
                final followButton = _buildFollowButton(context, user);
                final titleText = (user.name ?? user.username ?? 'Unknown').trim().isEmpty
                    ? 'Unknown'
                    : (user.name ?? user.username ?? 'Unknown');
                final subtitleText = (user.username != null && user.username!.isNotEmpty)
                    ? user.username!
                    : null;

                return Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => context.push('/profile/${user.id}'),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Row(
                        children: [
                          ChatAvatar(
                            radius: 24,
                            avatarUrl: user.avatarUrl,
                            username: user.username,
                            name: user.name,
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  titleText,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyLarge
                                      ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ) ??
                                      const TextStyle(
                                        fontWeight: FontWeight.w500,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (subtitleText != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    subtitleText,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .onSurfaceVariant,
                                            ) ??
                                        TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (followButton != null) ...[
                            const SizedBox(width: 8),
                            followButton,
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
      ),
    );
  }
}

