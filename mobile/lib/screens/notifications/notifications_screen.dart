import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:tripthread/models/unified_notification.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/services/api_service.dart';

/// Time grouping for notifications
enum NotificationTimeGroup { today, yesterday, thisWeek, older }

/// Unified notifications: follow requests in separate section, engagement with time groups.
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final userProvider = context.read<UserProvider>();
      await userProvider.loadUnifiedNotifications();
      if (!mounted) return;
      await userProvider.loadUnreadNotificationCount();
    });
  }

  List<UnifiedNotificationItem> _followRequests(
    List<UnifiedNotificationItem> all,
  ) => all.where((n) => n.isFollowRequest).toList();

  List<UnifiedNotificationItem> _engagementNotifications(
    List<UnifiedNotificationItem> all,
  ) => all
      .where((n) => n.isLike || n.isComment || n.isCommentReply || n.isTag)
      .toList();

  NotificationTimeGroup _timeGroup(String createdAt) {
    final dt = DateTime.tryParse(createdAt);
    if (dt == null) return NotificationTimeGroup.older;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final notifDate = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(notifDate).inDays;
    if (diff == 0) return NotificationTimeGroup.today;
    if (diff == 1) return NotificationTimeGroup.yesterday;
    if (diff <= 7) return NotificationTimeGroup.thisWeek;
    return NotificationTimeGroup.older;
  }

  Map<NotificationTimeGroup, List<UnifiedNotificationItem>> _groupByTime(
    List<UnifiedNotificationItem> items,
  ) {
    final grouped = <NotificationTimeGroup, List<UnifiedNotificationItem>>{
      NotificationTimeGroup.today: [],
      NotificationTimeGroup.yesterday: [],
      NotificationTimeGroup.thisWeek: [],
      NotificationTimeGroup.older: [],
    };
    for (final n in items) {
      grouped[_timeGroup(n.createdAt)]!.add(n);
    }
    return grouped;
  }

  String _sectionTitle(NotificationTimeGroup g) {
    switch (g) {
      case NotificationTimeGroup.today:
        return 'Today';
      case NotificationTimeGroup.yesterday:
        return 'Yesterday';
      case NotificationTimeGroup.thisWeek:
        return 'Last 7 days';
      case NotificationTimeGroup.older:
        return 'Older';
    }
  }

  /// Group key for engagement: same post or same comment.
  String _engagementGroupKey(UnifiedNotificationItem n) {
    final t = n.type;
    if (t == 'COMMENT_REPLY' &&
        n.parentCommentId != null &&
        n.parentCommentId!.isNotEmpty) {
      return '${t}_parent_${n.parentCommentId}';
    }
    final et = n.entityType ?? 'POST';
    final eid = n.entityId ?? n.postEntityId ?? n.id;
    return '${t}_${et}_$eid';
  }

  /// Groups engagement items by entity. Returns list of groups (each group = list of items).
  List<List<UnifiedNotificationItem>> _groupEngagementByEntity(
    List<UnifiedNotificationItem> items,
  ) {
    if (items.isEmpty) return [];
    final map = <String, List<UnifiedNotificationItem>>{};
    for (final n in items) {
      final key = _engagementGroupKey(n);
      map.putIfAbsent(key, () => []).add(n);
    }
    return map.values.toList();
  }

  Future<void> _markNotificationsAsRead(
    List<UnifiedNotificationItem> notifications,
    UserProvider userProvider,
  ) async {
    if (notifications.isEmpty) return;
    final apiService = context.read<ApiService>();
    var shouldReconcileUnreadCount = false;

    for (final notification in notifications) {
      try {
        final response = await apiService.markNotificationRead(notification.id);
        if (response.success) {
          shouldReconcileUnreadCount = true;
          final changed = userProvider.markNotificationReadLocal(
            notification.id,
          );
          if (changed) {
            shouldReconcileUnreadCount = true;
          }
        }
      } catch (_) {}
    }

    if (shouldReconcileUnreadCount) {
      await userProvider.loadUnreadNotificationCount();
    }
  }

  void _navigateToThread(String tripId, {String? highlightEntryId}) {
    context.push(
      '/trip/$tripId/thread',
      extra: highlightEntryId != null && highlightEntryId.isNotEmpty
          ? {'highlightEntryId': highlightEntryId}
          : null,
    );
  }

  Future<void> _onTapEngagementGroup(
    List<UnifiedNotificationItem> group,
    UserProvider userProvider,
  ) async {
    if (group.isEmpty) return;
    final first = group.first;
    final navEntityType = first.navEntityType;
    final navEntityId = first.navEntityId;
    final threadEntryId = first.highlightThreadEntryId;
    final threadTripId = first.tripId;
    final isThreadEntryNavigation =
        navEntityType == 'TRIP_THREAD_ENTRY' || threadEntryId != null;

    if (isThreadEntryNavigation) {
      if (threadTripId == null || threadTripId.isEmpty) {
        context.go('/home');
        return;
      }
      _navigateToThread(
        threadTripId,
        highlightEntryId: threadEntryId ?? navEntityId,
      );
      unawaited(_markNotificationsAsRead(group, userProvider));
      return;
    }

    if (first.isTag && first.tripId != null && first.tripId!.isNotEmpty) {
      _navigateToThread(first.tripId!, highlightEntryId: first.threadEntryId);
      unawaited(_markNotificationsAsRead(group, userProvider));
      return;
    }

    final scrollToCommentId = first.scrollToCommentId;

    if (navEntityType == null || navEntityId == null || navEntityId.isEmpty) {
      context.go('/home');
      return;
    }

    context.push(
      '/post/$navEntityType/$navEntityId',
      extra: scrollToCommentId != null && scrollToCommentId.isNotEmpty
          ? {'scrollToCommentId': scrollToCommentId}
          : null,
    );
    unawaited(_markNotificationsAsRead(group, userProvider));
  }

  Future<void> _handleAcceptRequest(String requestId, String actorName) async {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    final success = await userProvider.acceptFollowRequest(requestId);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Accepted follow request from $actorName'),
          backgroundColor: Colors.green,
        ),
      );
      if (mounted && currentUserId != null) {
        await userProvider.loadUnifiedNotifications();
        await userProvider.loadUnreadNotificationCount();
        await userProvider.loadProfileData(currentUserId, currentUserId);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userProvider.followRequestsError ?? 'Failed to accept request',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleRejectRequest(String requestId, String actorName) async {
    if (!mounted) return;
    final userProvider = context.read<UserProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    final success = await userProvider.rejectFollowRequest(requestId);
    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejected follow request from $actorName'),
          backgroundColor: Colors.orange,
        ),
      );
      if (mounted && currentUserId != null) {
        await userProvider.loadUnifiedNotifications();
        await userProvider.loadUnreadNotificationCount();
        await userProvider.loadProfileData(currentUserId, currentUserId);
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userProvider.followRequestsError ?? 'Failed to reject request',
          ),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _onTapNotification(UnifiedNotificationItem n) async {
    final userProvider = context.read<UserProvider>();

    if (n.isFollowRequest) {
      context.push('/profile/${n.actor.id}');
      return;
    }

    final navEntityType = n.navEntityType;
    final navEntityId = n.navEntityId;
    final threadEntryId = n.highlightThreadEntryId;
    final isThreadEntryNavigation =
        navEntityType == 'TRIP_THREAD_ENTRY' || threadEntryId != null;

    if (isThreadEntryNavigation) {
      if (n.tripId == null || n.tripId!.isEmpty) {
        context.go('/home');
        return;
      }
      _navigateToThread(
        n.tripId!,
        highlightEntryId: threadEntryId ?? navEntityId,
      );
      unawaited(_markNotificationsAsRead([n], userProvider));
      return;
    }

    if (n.isTag) {
      if (n.tripId != null && n.tripId!.isNotEmpty) {
        _navigateToThread(n.tripId!, highlightEntryId: n.threadEntryId);
      } else if (n.navEntityType != null &&
          n.navEntityId != null &&
          n.navEntityId!.isNotEmpty) {
        context.push(
          '/post/${n.navEntityType}/${n.navEntityId}',
          extra: n.scrollToCommentId != null
              ? {'scrollToCommentId': n.scrollToCommentId}
              : null,
        );
      } else {
        context.go('/home');
      }
      unawaited(_markNotificationsAsRead([n], userProvider));
      return;
    }

    if (n.isLike || n.isComment || n.isCommentReply) {
      final scrollToCommentId = n.scrollToCommentId;

      if (navEntityType == null || navEntityId == null) {
        context.go('/home');
        return;
      }

      context.push(
        '/post/$navEntityType/$navEntityId',
        extra: scrollToCommentId != null
            ? {'scrollToCommentId': scrollToCommentId}
            : null,
      );
      unawaited(_markNotificationsAsRead([n], userProvider));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Notifications'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
        ),
        body: Consumer<UserProvider>(
          builder: (context, userProvider, child) {
            if (userProvider.isNotificationsLoading &&
                userProvider.unifiedNotifications.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (userProvider.unifiedNotificationsError != null &&
                userProvider.unifiedNotifications.isEmpty) {
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
                        userProvider.unifiedNotificationsError!,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () =>
                            userProvider.loadUnifiedNotifications(),
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final followReqs = _followRequests(
              userProvider.unifiedNotifications,
            );
            final engagement = _engagementNotifications(
              userProvider.unifiedNotifications,
            );

            if (followReqs.isEmpty && engagement.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_none_outlined,
                      size: 64,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No notifications yet',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Likes, comments and follow requests\nwill appear here',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(
                          context,
                        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                await userProvider.loadUnifiedNotifications();
                await userProvider.loadUnreadNotificationCount();
              },
              child: ListView(
                padding: const EdgeInsets.only(bottom: 24),
                children: [
                  if (followReqs.isNotEmpty) ...[
                    _buildFollowRequestsSummaryTile(context, followReqs),
                    const SizedBox(height: 16),
                  ],
                  ..._buildTimeGroupedSections(
                    context,
                    engagement,
                    userProvider,
                  ),
                  if (userProvider.notificationsLoadMore)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (userProvider.hasMoreNotifications)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: Center(
                        child: TextButton.icon(
                          onPressed: () =>
                              userProvider.loadMoreUnifiedNotifications(),
                          icon: Icon(
                            Icons.keyboard_arrow_down,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          label: Text(
                            'Show more',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// Instagram-style: stacked avatars (last 2), "Kunal + 1" text, chevron.
  Widget _buildFollowRequestsSummaryTile(
    BuildContext context,
    List<UnifiedNotificationItem> followReqs,
  ) {
    final count = followReqs.length;
    final first = followReqs.first.actor.displayName;
    final others = count - 1;
    String label;
    if (others == 0) {
      label = '$first requested to follow you';
    } else {
      label = '$first +$others requested to follow you';
    }

    final avatarSize = 40.0;
    final overlap = 16.0;
    final avatarsToShow = followReqs.take(2).toList();

    return Material(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      child: InkWell(
        onTap: () => context.push('/follow-requests'),
        child: Container(
          decoration: BoxDecoration(
            border: Border(
              left: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 4,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width:
                      avatarSize +
                      (avatarsToShow.length > 1 ? avatarSize - overlap : 0),
                  height: avatarSize,
                  child: Stack(
                    children: [
                      for (var i = 0; i < avatarsToShow.length; i++)
                        Positioned(
                          left: i * (avatarSize - overlap),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: avatarSize / 2 - 1,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              backgroundImage:
                                  avatarsToShow[i].actor.avatarUrl != null &&
                                      avatarsToShow[i]
                                          .actor
                                          .avatarUrl!
                                          .isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      avatarsToShow[i].actor.avatarUrl!,
                                    )
                                  : null,
                              child:
                                  avatarsToShow[i].actor.avatarUrl == null ||
                                      avatarsToShow[i].actor.avatarUrl!.isEmpty
                                  ? Text(
                                      avatarsToShow[i]
                                              .actor
                                              .displayName
                                              .isNotEmpty
                                          ? avatarsToShow[i].actor.displayName
                                                .substring(0, 1)
                                                .toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                        fontSize: 16,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Follow requests',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  /// Whether this time group uses grouped (summary) tiles.
  bool _useGroupedTiles(NotificationTimeGroup g) =>
      g == NotificationTimeGroup.thisWeek || g == NotificationTimeGroup.older;

  List<Widget> _buildTimeGroupedSections(
    BuildContext context,
    List<UnifiedNotificationItem> engagement,
    UserProvider userProvider,
  ) {
    final grouped = _groupByTime(engagement);
    final order = [
      NotificationTimeGroup.today,
      NotificationTimeGroup.yesterday,
      NotificationTimeGroup.thisWeek,
      NotificationTimeGroup.older,
    ];
    final widgets = <Widget>[];
    for (final g in order) {
      final items = grouped[g]!;
      if (items.isEmpty) continue;
      widgets.add(_sectionHeader(context, _sectionTitle(g)));
      if (_useGroupedTiles(g)) {
        final entityGroups = _groupEngagementByEntity(items);
        for (final group in entityGroups) {
          widgets.add(
            _buildEngagementSummaryTile(context, group, userProvider),
          );
        }
      } else {
        for (final n in items) {
          widgets.add(_buildNotificationTile(context, n, userProvider));
        }
      }
    }
    return widgets;
  }

  Widget _buildEngagementSummaryTile(
    BuildContext context,
    List<UnifiedNotificationItem> group,
    UserProvider userProvider,
  ) {
    if (group.isEmpty) return const SizedBox.shrink();
    final first = group.first;
    final count = group.length;
    final firstName = first.actor.displayName;
    final others = count - 1;

    String label;
    String subtitle;
    if (first.isLike) {
      if (first.entityType == 'COMMENT') {
        label = others == 0
            ? '$firstName liked your comment'
            : '$firstName +$others liked your comment';
        subtitle = 'Likes';
      } else {
        label = others == 0
            ? '$firstName liked your post'
            : '$firstName +$others liked your post';
        subtitle = 'Likes';
      }
    } else if (first.isCommentReply) {
      label = others == 0
          ? '$firstName replied to your comment'
          : '$firstName +$others replied to your comment';
      subtitle = 'Replies';
    } else if (first.isTag) {
      label = others == 0
          ? '$firstName tagged you in a post'
          : '$firstName +$others tagged you in a post';
      subtitle = 'Tags';
    } else {
      label = others == 0
          ? '$firstName commented on your post'
          : '$firstName +$others commented on your post';
      subtitle = 'Comments';
    }

    final previews = group
        .map((n) => n.contentPreview)
        .whereType<String>()
        .where((s) => s.isNotEmpty)
        .toList();
    final contentPreview = previews.isNotEmpty ? previews.first : null;

    final hasUnread = group.any(
      (n) => n.readAt == null || (n.readAt?.isEmpty ?? true),
    );
    final avatarSize = 40.0;
    final overlap = 16.0;
    final avatarsToShow = group.take(2).toList();

    return Material(
      color: hasUnread
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _onTapEngagementGroup(group, userProvider),
        child: Container(
          decoration: BoxDecoration(
            border: hasUnread
                ? Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 4,
                    ),
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                SizedBox(
                  width:
                      avatarSize +
                      (avatarsToShow.length > 1 ? avatarSize - overlap : 0),
                  height: avatarSize,
                  child: Stack(
                    children: [
                      for (var i = 0; i < avatarsToShow.length; i++)
                        Positioned(
                          left: i * (avatarSize - overlap),
                          child: Container(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Theme.of(
                                  context,
                                ).scaffoldBackgroundColor,
                                width: 2,
                              ),
                            ),
                            child: CircleAvatar(
                              radius: avatarSize / 2 - 1,
                              backgroundColor: Theme.of(
                                context,
                              ).colorScheme.primaryContainer,
                              backgroundImage:
                                  avatarsToShow[i].actor.avatarUrl != null &&
                                      avatarsToShow[i]
                                          .actor
                                          .avatarUrl!
                                          .isNotEmpty
                                  ? CachedNetworkImageProvider(
                                      avatarsToShow[i].actor.avatarUrl!,
                                    )
                                  : null,
                              child:
                                  avatarsToShow[i].actor.avatarUrl == null ||
                                      avatarsToShow[i].actor.avatarUrl!.isEmpty
                                  ? Text(
                                      avatarsToShow[i]
                                              .actor
                                              .displayName
                                              .isNotEmpty
                                          ? avatarsToShow[i].actor.displayName
                                                .substring(0, 1)
                                                .toUpperCase()
                                          : '?',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onPrimaryContainer,
                                        fontSize: 16,
                                      ),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        subtitle,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant
                                  .withValues(alpha: 0.8),
                            ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        label,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (contentPreview != null &&
                          contentPreview.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          '"${contentPreview.length > 50 ? '${contentPreview.substring(0, 50)}...' : contentPreview}"',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant
                                    .withValues(alpha: 0.9),
                                fontStyle: FontStyle.italic,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_right,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotificationTile(
    BuildContext context,
    UnifiedNotificationItem n,
    UserProvider userProvider,
  ) {
    final actorName = n.actor.displayName;
    String title;
    String? subtitle;
    IconData icon;
    if (n.isFollowRequest) {
      title = '$actorName requested to follow you';
      subtitle = null;
      icon = Icons.person_add;
    } else if (n.isLike) {
      if (n.entityType == 'COMMENT') {
        title = '$actorName liked your comment';
        subtitle = n.contentPreview != null && n.contentPreview!.isNotEmpty
            ? '"${n.contentPreview!.length > 60 ? '${n.contentPreview!.substring(0, 60)}...' : n.contentPreview}"'
            : null;
      } else {
        title = '$actorName liked your post';
        subtitle = null;
      }
      icon = Icons.favorite;
    } else if (n.isCommentReply) {
      title = '$actorName replied to your comment';
      subtitle = n.contentPreview != null && n.contentPreview!.isNotEmpty
          ? '"${n.contentPreview!.length > 60 ? '${n.contentPreview!.substring(0, 60)}...' : n.contentPreview}"'
          : null;
      icon = Icons.reply;
    } else if (n.isTag) {
      title = '$actorName tagged you in a post';
      subtitle = n.contentPreview != null && n.contentPreview!.isNotEmpty
          ? '"${n.contentPreview!.length > 60 ? '${n.contentPreview!.substring(0, 60)}...' : n.contentPreview}"'
          : null;
      icon = Icons.tag;
    } else {
      title = '$actorName commented on your post';
      subtitle = n.contentPreview != null && n.contentPreview!.isNotEmpty
          ? '"${n.contentPreview!.length > 60 ? '${n.contentPreview!.substring(0, 60)}...' : n.contentPreview}"'
          : null;
      icon = Icons.comment;
    }

    final isUnread =
        n.isFollowRequest ||
        ((n.isLike || n.isComment || n.isCommentReply || n.isTag) &&
            (n.readAt == null || (n.readAt?.isEmpty ?? true)));
    final backgroundColor = isUnread
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
        : Colors.transparent;

    return Material(
      color: backgroundColor,
      child: InkWell(
        onTap: () => _onTapNotification(n),
        child: Container(
          decoration: BoxDecoration(
            border: isUnread
                ? Border(
                    left: BorderSide(
                      color: Theme.of(context).colorScheme.primary,
                      width: 4,
                    ),
                  )
                : null,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.primaryContainer,
                  backgroundImage:
                      n.actor.avatarUrl != null && n.actor.avatarUrl!.isNotEmpty
                      ? CachedNetworkImageProvider(n.actor.avatarUrl!)
                      : null,
                  child: n.actor.avatarUrl == null || n.actor.avatarUrl!.isEmpty
                      ? Text(
                          actorName.isNotEmpty
                              ? actorName.substring(0, 1).toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimaryContainer,
                            fontSize: 18,
                          ),
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
                          Icon(
                            icon,
                            size: 18,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              title,
                              style: Theme.of(context).textTheme.bodyLarge
                                  ?.copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                      if (subtitle != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                                fontStyle: FontStyle.italic,
                              ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      if (n.isFollowRequest) ...[
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            TextButton(
                              onPressed: () => _handleAcceptRequest(
                                n.followRequestId ?? n.id,
                                actorName,
                              ),
                              child: const Text('Accept'),
                            ),
                            const SizedBox(width: 8),
                            TextButton(
                              onPressed: () => _handleRejectRequest(
                                n.followRequestId ?? n.id,
                                actorName,
                              ),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
