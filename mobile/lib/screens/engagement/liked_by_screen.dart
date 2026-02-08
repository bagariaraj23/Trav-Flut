import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/models/user.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:go_router/go_router.dart';

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

  /// Safe one-letter initial for avatar. Never null, never throws.
  String _userDisplayInitial(User user) {
    final s = (user.name ?? user.username ?? 'U').trim();
    if (s.isEmpty) return 'U';
    return s.substring(0, 1).toUpperCase();
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to determine follow status'),
          backgroundColor: Colors.red,
        ),
      );
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
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(success ? actionMessage : errorMessage),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );
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
      body: Consumer2<EngagementProvider, UserProvider>(
        builder: (context, engagementProvider, userProvider, child) {
          final users = engagementProvider.getLikeUsersList('${widget.entityType}:${widget.entityId}');
          final isLoading = engagementProvider.isLoadingUsers('${widget.entityType}:${widget.entityId}');
          final error = engagementProvider.error;

          if (isLoading && users.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (error != null && users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(error),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: _loadUsers,
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (users.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.favorite_border,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No likes yet',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
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
                final initial = _userDisplayInitial(user);
                final titleText = (user.name ?? user.username ?? 'Unknown').trim().isEmpty
                    ? 'Unknown'
                    : (user.name ?? user.username ?? 'Unknown');
                final subtitleText = (user.username != null && user.username!.isNotEmpty)
                    ? '@${user.username!}'
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
                          CircleAvatar(
                            radius: 24,
                            backgroundImage: user.avatarUrl != null &&
                                    user.avatarUrl!.isNotEmpty
                                ? CachedNetworkImageProvider(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null ||
                                    (user.avatarUrl?.isEmpty ?? true)
                                ? Text(
                                    initial,
                                    style: const TextStyle(fontSize: 18),
                                  )
                                : null,
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
    );
  }
}

