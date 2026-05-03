import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/engagement_provider.dart';
import 'package:tripthread/services/trip_service.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/screens/discover/discover_tab.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/widgets/engagement/engagement_action_bar.dart';
import 'package:tripthread/widgets/sheets/comment_bottom_sheet.dart';
import 'package:tripthread/widgets/sheets/share_bottom_sheet.dart';
import 'package:tripthread/widgets/floating_trip_nav_button.dart';
import 'package:tripthread/widgets/logout_dialog.dart';

class HomeScreen extends StatefulWidget {
  final int initialTab;

  const HomeScreen({super.key, this.initialTab = 0});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    debugPrint(
      '[HomeScreen] Initializing with initialTab: ${widget.initialTab}',
    );
    _currentIndex = widget.initialTab;
    // Initialize trip provider and load pending follow requests for notifications
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      debugPrint('[HomeScreen] Initializing providers');
      final tripProvider = context.read<TripProvider>();
      await tripProvider.initialize();
      debugPrint('[HomeScreen] TripProvider initialized');

      // Check if widget is still mounted before using context
      if (!mounted) return;

      // Redirect to thread only once on initial app load when there's an ongoing trip.
      // After that, user can freely navigate back to home/trips without redirect loop.
      final router = GoRouter.of(context);
      final routeExtra = GoRouterState.of(context).extra;
      final isExplicitHome =
          routeExtra is Map && routeExtra['explicitHome'] == true;
      final hasCompletedInitial =
          tripProvider.hasCompletedInitialOngoingTripRedirect;

      if (!isExplicitHome &&
          !hasCompletedInitial &&
          tripProvider.hasOngoingTrip &&
          tripProvider.currentTrip != null) {
        final currentLocation = router.routerDelegate.currentConfiguration.uri
            .toString();

        // Only redirect if we're on /home (not /trips or other tabs)
        if (currentLocation == '/home' || currentLocation == '/') {
          final tripId = tripProvider.currentTrip!.id;
          debugPrint(
            '[HomeScreen] Initial load with ongoing trip, redirecting to /trip/$tripId/thread',
          );
          tripProvider.markInitialOngoingTripRedirectComplete();
          router.go('/trip/$tripId/thread');
          return;
        }
      }

      // Load pending follow requests and unread notification count to update notification badge
      if (!mounted) return;
      context.read<UserProvider>().loadPendingFollowRequests();
      debugPrint(
        '[HomeScreen] Loading pending follow requests for notifications',
      );
      final userProvider = context.read<UserProvider>();
      userProvider.loadPendingFollowRequests();
      userProvider.loadUnreadNotificationCount();
      debugPrint('[HomeScreen] Loading notifications for badge');
    });
  }

  final List<Widget> _screens = [
    const FeedTab(),
    const TripsTab(),
    const DiscoverTab(),
    const ProfileTab(),
  ];

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (_currentIndex != 0) {
          setState(() => _currentIndex = 0);
          return;
        }
        final exit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Exit TripThread?'),
            content: const Text('Close the app?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Exit'),
              ),
            ],
          ),
        );
        if (exit == true && context.mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        body: Stack(
          children: [
            _screens[_currentIndex],
            // Floating navigation button for ongoing trips
            const FloatingTripNavButton(),
          ],
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
            if (index == 2) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                context.read<FeedProvider>().loadDiscoverTrips(refresh: true);
              });
            }
          },
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_outlined),
              activeIcon: Icon(Icons.home),
              label: 'Feed',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.map_outlined),
              activeIcon: Icon(Icons.map),
              label: 'Trips',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: 'Discover',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outlined),
              activeIcon: Icon(Icons.person),
              label: 'Profile',
            ),
          ],
        ),
      ),
    );
  }
}

class FeedTab extends StatelessWidget {
  const FeedTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const HomeFeedScreen();
  }
}

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadInitialFeed();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _loadInitialFeed() {
    debugPrint('[HomeFeedScreen] Loading initial feed');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        debugPrint('[HomeFeedScreen] Calling loadHomeFeed with refresh=true');
        context.read<FeedProvider>().loadHomeFeed(refresh: true);
      }
    });
  }

  void _openFinalPostDetail(BuildContext context, TripFinalPost post) {
    context.push('/post/TRIP_FINAL_POST/${post.id}');
  }

  Future<void> _confirmDeleteFinalPost(
    BuildContext context,
    TripFinalPost post,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete post?'),
        content: const Text(
          'This removes the final post from feeds and deletes its likes and comments. You can create a new final post from the trip later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(
              'Delete',
              style: TextStyle(color: Theme.of(ctx).colorScheme.error),
            ),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    final tripService = context.read<TripService>();
    final res = await tripService.deleteFinalPost(post.tripId);
    if (!context.mounted) return;
    if (res.success) {
      context.read<FeedProvider>().removeHomeFeedPostById(post.id);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Post deleted')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.error ?? 'Could not delete post')),
      );
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      debugPrint(
        '[HomeFeedScreen] Near end of scroll, checking for more posts',
      );
      final feedProvider = context.read<FeedProvider>();
      if (feedProvider.hasMoreHomeFeedPosts &&
          !feedProvider.isHomeFeedLoading) {
        debugPrint('[HomeFeedScreen] Loading more home feed posts');
        feedProvider.loadHomeFeed();
      } else {
        debugPrint('[HomeFeedScreen] No more posts to load or already loading');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('TripThread'),
        actions: [
          IconButton(
            icon: const Icon(Icons.chat_bubble_outline),
            tooltip: 'Messages',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Direct messages are coming soon.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          // Combined Notification Icon
          Consumer2<UserProvider, TripProvider>(
            builder: (context, userProvider, tripProvider, child) {
              final totalPending =
                  userProvider.pendingFollowRequests.length +
                  tripProvider.pendingTripInvitations.length +
                  userProvider.unreadNotificationCount;
              return Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.notifications_outlined),
                    onPressed: () {
                      context.push('/notifications');
                    },
                  ),
                  if (totalPending > 0)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '$totalPending',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
      body: Consumer<FeedProvider>(
        builder: (context, feedProvider, child) {
          if (feedProvider.homeFeedPosts.isEmpty &&
              feedProvider.isHomeFeedLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (feedProvider.homeFeedPosts.isEmpty &&
              feedProvider.homeFeedError == null) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.feed_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'No posts yet',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Follow some travelers to see their amazing stories',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            );
          }

          if (feedProvider.homeFeedError != null) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline, size: 64, color: Colors.red[300]),
                  const SizedBox(height: 16),
                  Text(
                    'Error loading feed',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.red[300],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    feedProvider.homeFeedError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      feedProvider.clearHomeFeedError();
                      feedProvider.loadHomeFeed(refresh: true);
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              feedProvider.loadHomeFeed(refresh: true);
            },
            child: ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: feedProvider.homeFeedPosts.length + 1,
              itemBuilder: (context, index) {
                if (index == feedProvider.homeFeedPosts.length) {
                  // Loading indicator at the bottom
                  if (feedProvider.isHomeFeedLoading &&
                      feedProvider.hasMoreHomeFeedPosts) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  return const SizedBox.shrink();
                }

                final post = feedProvider.homeFeedPosts[index];
                return _buildFinalPostCard(context, post);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildFinalPostCard(BuildContext context, TripFinalPost post) {
    final authUserId = context.read<AuthProvider>().currentUser?.id;
    final tripOwnerId = post.trip?.userId ?? post.trip?.user?.id;
    final isOwner =
        authUserId != null && tripOwnerId != null && authUserId == tripOwnerId;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      elevation: 2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with user info (avatar and name tappable → profile)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                GestureDetector(
                  onTap: () {
                    final userId = post.trip?.userId ?? post.trip?.user?.id;
                    if (userId != null) context.push('/profile/$userId');
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    backgroundImage: post.trip?.user?.avatarUrl != null
                        ? NetworkImage(post.trip!.user!.avatarUrl!)
                        : null,
                    child: post.trip?.user?.avatarUrl == null
                        ? Icon(Icons.person, color: Colors.white, size: 20)
                        : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: () {
                          final userId =
                              post.trip?.userId ?? post.trip?.user?.id;
                          if (userId != null) context.push('/profile/$userId');
                        },
                        child: Text(
                          post.trip?.user?.name ??
                              post.trip?.user?.username ??
                              'Travel Story',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                      Text(
                        _formatDateTime(post.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isOwner)
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (value) async {
                      if (!context.mounted) return;
                      if (value == 'edit') {
                        context.push('/trip/${post.tripId}/final-post');
                      } else if (value == 'delete') {
                        await _confirmDeleteFinalPost(context, post);
                      }
                    },
                    itemBuilder: (ctx) => const [
                      PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(value: 'delete', child: Text('Delete')),
                    ],
                  )
                else
                  const SizedBox(width: 48),
              ],
            ),
          ),
          InkWell(
            onTap: () => _openFinalPostDetail(context, post),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
                                  alpha: Theme.of(context).brightness ==
                                          Brightness.dark
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
                                        alpha: Theme.of(context).brightness ==
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
                      Text(
                        post.summaryText,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                      if (post.caption != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          post.caption!,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(
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
                                onCommentTap: () {
                                  showModalBottomSheet(
                                    context: context,
                                    isScrollControlled: true,
                                    backgroundColor: Colors.transparent,
                                    builder: (context) => CommentBottomSheet(
                                      entityType: 'TRIP_FINAL_POST',
                                      entityId: post.id,
                                    ),
                                  );
                                },
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
                                  final engagementProvider = context
                                      .read<EngagementProvider>();
                                  final newLikeCount = engagementProvider
                                      .getLikeCount(post.id);
                                  final newHasLiked =
                                      engagementProvider.isLiked(post.id);

                                  final feedProvider =
                                      context.read<FeedProvider>();
                                  final updatedPost = post.copyWith(
                                    likeCount: newLikeCount,
                                    hasLiked: newHasLiked,
                                  );
                                  final index = feedProvider.homeFeedPosts
                                      .indexWhere((p) => p.id == post.id);
                                  if (index >= 0) {
                                    feedProvider.updatePost(index, updatedPost);
                                  }
                                },
                              ),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              context.push(
                                '/trip/${post.tripId}',
                                extra: {'from': '/home'},
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
          ),
        ],
      ),
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }
}

class TripsTab extends StatefulWidget {
  const TripsTab({super.key});

  @override
  State<TripsTab> createState() => _TripsTabState();
}

class _TripsTabState extends State<TripsTab> {
  Future<void> _handleCreateTrip(
    BuildContext context,
    TripProvider tripProvider,
  ) async {
    // Check for existing trips
    final conflictInfo = await tripProvider.checkTripConflicts();

    if (conflictInfo == null) {
      // No conflicts, proceed directly
      if (context.mounted) {
        context.push('/create-trip', extra: {'from': '/home'});
      }
      return;
    }

    // If there's an ongoing trip, button should be disabled (this shouldn't be called)
    // But handle it just in case
    if (conflictInfo.hasOngoingTrip) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'You have an ongoing trip. Please end it before starting a new one.',
            ),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Check if there's a future trip - show warning dialog
    if (!conflictInfo.hasFutureTrip) {
      // No conflicts, proceed directly
      if (context.mounted) {
        context.push('/create-trip', extra: {'from': '/home'});
      }
      return;
    }

    // Show warning dialog for future trip
    if (!context.mounted) return;

    final existingTrip = conflictInfo.futureTrip;

    final shouldContinue = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title
              Text(
                'Future Trip Scheduled',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 24),

              // Trip Info Card
              if (existingTrip != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outline.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.airplane_ticket_rounded,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              existingTrip.title,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            size: 16,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            '${_formatDate(existingTrip.startDate)}${existingTrip.endDate != null ? ' - ${_formatDate(existingTrip.endDate!)}' : ''}',
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // Warning Message
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Theme.of(
                    context,
                  ).colorScheme.errorContainer.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Text(
                  'Creating a new trip will replace your scheduled trip. The scheduled trip will be cancelled.',
                  textAlign: TextAlign.left,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 12,
                    height: 1.4,
                    fontWeight: FontWeight.w400,
                    letterSpacing: 0.1,
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Action Buttons - Bottom Right Aligned
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (existingTrip != null)
                      OutlinedButton(
                        onPressed: () {
                          Navigator.of(context).pop(false);
                          context.push('/trip/${existingTrip.id}');
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: 6,
                            horizontal: 12,
                          ),
                          minimumSize: const Size(0, 32),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        child: const Text(
                          'View Trip',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    if (existingTrip != null) const SizedBox(height: 8),
                    // Continue & replace and Cancel on same line
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 12,
                            ),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.error,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 12,
                            ),
                            minimumSize: const Size(0, 32),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            elevation: 0,
                          ),
                          child: const Text(
                            'Continue & replace',
                            style: TextStyle(fontSize: 13),
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
      ),
    );

    if (shouldContinue == true && context.mounted) {
      // Store replaceExisting flag in extra
      context.push(
        '/create-trip',
        extra: {'from': '/home', 'replaceExisting': true},
      );
    }
  }

  String _formatDate(DateTime date) {
    // Extract only date components to avoid timezone issues
    // Use UTC date components to ensure consistent display
    final dateOnly = DateTime.utc(date.year, date.month, date.day);
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[dateOnly.month - 1]} ${dateOnly.day}, ${dateOnly.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: const Text('My Trips'),
        actions: [
          Consumer<TripProvider>(
            builder: (context, tripProvider, child) {
              // Check if there's an ongoing trip to disable the button
              final hasOngoingTrip = tripProvider.hasOngoingTrip;
              return IconButton(
                icon: const Icon(Icons.add),
                onPressed: hasOngoingTrip
                    ? null
                    : () => _handleCreateTrip(context, tripProvider),
                tooltip: hasOngoingTrip
                    ? 'End your ongoing trip before creating a new one'
                    : 'Create new trip',
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Consumer<TripProvider>(
          builder: (context, tripProvider, child) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (tripProvider.currentTrip != null &&
                      tripProvider.currentTrip!.status == TripStatus.ongoing)
                    _buildOngoingTripBanner(context, tripProvider.currentTrip!),
                  _buildTripsContent(context, tripProvider),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTripsContent(BuildContext context, TripProvider tripProvider) {
    if (tripProvider.isLoading) {
      return const Padding(
        padding: EdgeInsets.all(48.0),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    final trips = tripProvider.trips;
    if (trips.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.map_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(height: 16),
              Text(
                'No Trips Yet',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Start documenting your travel adventures',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: tripProvider.hasOngoingTrip
                    ? null
                    : () => _handleCreateTrip(context, tripProvider),
                icon: const Icon(Icons.add),
                label: const Text('Start Your First Trip'),
              ),
            ],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...trips.map((trip) => _buildTripCard(context, trip)),
          const SizedBox(height: 80), // Bottom padding for FAB
        ],
      ),
    );
  }

  Widget _buildOngoingTripBanner(BuildContext context, Trip trip) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Container(
      margin: EdgeInsets.all(isLandscape ? 12 : 16),
      padding: EdgeInsets.all(isLandscape ? 12 : 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(
                Icons.flight_takeoff,
                color: Colors.white,
                size: isLandscape ? 18 : 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Ongoing Trip',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: isLandscape ? 14 : 16,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'LIVE',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: isLandscape ? 10 : 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: isLandscape ? 6 : 8),
          Text(
            trip.title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: isLandscape ? 18 : 22,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            trip.destinations.join(', '),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: isLandscape ? 12 : 14,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          SizedBox(height: isLandscape ? 8 : 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => context.push(
                    '/trip/${trip.id}/thread',
                    extra: {'from': '/trip/${trip.id}'},
                  ),
                  icon: Icon(Icons.add, size: isLandscape ? 16 : 18),
                  label: Text(
                    'Add Entry',
                    style: TextStyle(fontSize: isLandscape ? 12 : 14),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: Theme.of(context).colorScheme.primary,
                    padding: EdgeInsets.symmetric(
                      vertical: isLandscape ? 8 : 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: () =>
                    context.push('/trip/${trip.id}', extra: {'from': '/trips'}),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.white),
                  foregroundColor: Colors.white,
                  padding: EdgeInsets.symmetric(
                    horizontal: isLandscape ? 12 : 16,
                    vertical: isLandscape ? 8 : 12,
                  ),
                ),
                child: Text(
                  'View',
                  style: TextStyle(fontSize: isLandscape ? 12 : 14),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTripCard(BuildContext context, Trip trip) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        onTap: () =>
            context.push('/trip/${trip.id}', extra: {'from': '/trips'}),
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover image
            Container(
              height: 200,
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(12),
                ),
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.06
                      : 0.03,
                ),
              ),
              child: () {
                final coverUrl = trip.coverMedia?.url;
                if (coverUrl == null) {
                  return _buildPlaceholderImage(context, trip);
                }
                return ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(12),
                  ),
                  child: Image.network(
                    buildOptimizedImageUrl(coverUrl, width: 1600),
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return _buildPlaceholderImage(context, trip);
                    },
                  ),
                );
              }(),
            ),
            // Trip info
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          trip.title,
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      _buildStatusBadge(context, trip.status),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Icon(
                        Icons.location_on,
                        size: 16,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          trip.destinations.join(', '),
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),
                  if (trip.description != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      trip.description!,
                      style: Theme.of(context).textTheme.bodyMedium,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _buildStatChip(
                        context,
                        Icons.timeline,
                        '${trip.entryCount} entries',
                      ),
                      const SizedBox(width: 8),
                      if (trip.participantCount > 0)
                        _buildStatChip(
                          context,
                          Icons.people,
                          '${trip.participantCount} people',
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

  Widget _buildPlaceholderImage(BuildContext context, Trip trip) {
    return Container(
      width: double.infinity,
      height: 200,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.travel_explore, size: 48, color: Colors.white),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              trip.destinations.isNotEmpty
                  ? trip.destinations.first
                  : trip.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BuildContext context, TripStatus status) {
    Color color;
    String label;

    switch (status) {
      case TripStatus.upcoming:
        color = Colors.orange;
        label = 'Upcoming';
        break;
      case TripStatus.ongoing:
        color = Colors.green;
        label = 'Ongoing';
        break;
      case TripStatus.ended:
        color = Colors.blue;
        label = 'Completed';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStatChip(BuildContext context, IconData icon, String text) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: isDark ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class ProfileTab extends StatelessWidget {
  const ProfileTab({super.key});

  static String _formatDateForCard(DateTime date) {
    // Extract only date components to avoid timezone issues
    final dateOnly = DateTime.utc(date.year, date.month, date.day);
    return '${dateOnly.day}/${dateOnly.month}/${dateOnly.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthProvider, TripProvider>(
      builder: (context, authProvider, tripProvider, child) {
        final user = authProvider.currentUser;

        if (user == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // Ensure stats are loaded for the current user (once)
        final userProvider = context.read<UserProvider>();
        final stats = userProvider.getUserStats(user.id);
        if (stats == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              context.read<UserProvider>().fetchUserStats(user.id);
            }
          });
        }

        final pendingTripInvitations = tripProvider.pendingTripInvitations;

        return Scaffold(
          appBar: AppBar(
            centerTitle: false,
            title: const Text('Profile'),
            actions: [
              // Trip Invitations (own profile tab)
              Stack(
                alignment: Alignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.mail_outline),
                    tooltip: 'Trip Invitations',
                    onPressed: () => context.push('/trip-invites'),
                  ),
                  if (pendingTripInvitations.isNotEmpty)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 14,
                          minHeight: 14,
                        ),
                        child: Text(
                          '${pendingTripInvitations.length}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.person_add_outlined),
                tooltip: 'Follow Requests',
                onPressed: () async {
                  final currentUser = await userProvider.getCurrentUser();
                  if (currentUser != null) {
                    userProvider.getDetailedFollowStatus(currentUser.id);
                  }
                  if (context.mounted) {
                    context.go('/follow-requests');
                  }
                },
              ),
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                onPressed: () => context.push('/settings'),
              ),
              IconButton(
                icon: const Icon(Icons.logout),
                onPressed: () => showLogoutDialog(context),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Profile Header
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Avatar
                      Center(
                        child: GestureDetector(
                          onTap: user.avatarUrl == null
                              ? null
                              : () {
                                  showDialog(
                                    context: context,
                                    barrierColor: Colors.black.withValues(
                                      alpha: 0.7,
                                    ),
                                    builder: (dialogContext) {
                                      return GestureDetector(
                                        onTap: () =>
                                            Navigator.of(dialogContext).pop(),
                                        child: Dialog(
                                          backgroundColor: Colors.transparent,
                                          insetPadding: const EdgeInsets.all(
                                            32,
                                          ),
                                          child: Container(
                                            padding: const EdgeInsets.all(16),
                                            decoration: BoxDecoration(
                                              color: Colors.black87,
                                              borderRadius:
                                                  BorderRadius.circular(24),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.black
                                                      .withValues(alpha: 0.4),
                                                  blurRadius: 20,
                                                  offset: const Offset(0, 8),
                                                ),
                                              ],
                                            ),
                                            child: CircleAvatar(
                                              radius: 120,
                                              backgroundImage: NetworkImage(
                                                user.avatarUrl!,
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  );
                                },
                          child: CircleAvatar(
                            radius: 40,
                            backgroundColor: Theme.of(
                              context,
                            ).colorScheme.primary,
                            backgroundImage: user.avatarUrl != null
                                ? NetworkImage(user.avatarUrl!)
                                : null,
                            child: user.avatarUrl == null
                                ? Text(
                                    user.name?.substring(0, 1).toUpperCase() ??
                                        'U',
                                    style: const TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  )
                                : null,
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Name
                      Text(
                        user.name ?? 'User',
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),

                      // Username
                      if (user.username != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          '@${user.username}',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],

                      // Bio
                      if (user.bio != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          user.bio!,
                          style: Theme.of(context).textTheme.bodyMedium,
                          textAlign: TextAlign.center,
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Stats Row
                      Consumer2<TripProvider, UserProvider>(
                        builder: (context, tripProvider, userProvider, child) {
                          final tripCount = tripProvider.trips.length;
                          final userStats = userProvider.getUserStats(user.id);
                          final followerCount = userStats?.followerCount ?? 0;
                          final followingCount = userStats?.followingCount ?? 0;
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _buildStatColumn(
                                context,
                                tripCount.toString(),
                                'Trips',
                              ),
                              _buildStatColumn(
                                context,
                                '$followerCount',
                                'Followers',
                                onTap: () {
                                  debugPrint(
                                    '[ProfileTab] Navigating to followers for user: ${user.id}',
                                  );
                                  context.push(
                                    '/profile/${user.id}/followers',
                                    extra: {'from': '/home'},
                                  );
                                },
                              ),
                              _buildStatColumn(
                                context,
                                '$followingCount',
                                'Following',
                                onTap: () {
                                  debugPrint(
                                    '[ProfileTab] Navigating to following for user: ${user.id}',
                                  );
                                  context.push(
                                    '/profile/${user.id}/following',
                                    extra: {'from': '/home'},
                                  );
                                },
                              ),
                            ],
                          );
                        },
                      ),

                      const SizedBox(height: 20),

                      // Edit Profile Button
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton(
                          onPressed: () {
                            context.push(
                              '/edit-profile',
                              extra: {'from': '/home'},
                            );
                          },
                          child: const Text('Edit Profile'),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Recent Trips Section
                Consumer<TripProvider>(
                  builder: (context, tripProvider, child) {
                    final recentTrips = tripProvider.trips.take(3).toList();

                    return Container(
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                'Recent Trips',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineSmall,
                              ),
                              const Spacer(),
                              if (tripProvider.trips.isNotEmpty)
                                TextButton(
                                  onPressed: () {
                                    context.go(
                                      '/trips',
                                      extra: {'from': '/home'},
                                    );
                                  },
                                  child: const Text('View All'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (recentTrips.isEmpty)
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.map_outlined,
                                    size: 48,
                                    color: Colors.grey,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No trips yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: Colors.grey,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Builder(
                                    builder: (context) => Text(
                                      'Start documenting your adventures!',
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: recentTrips.map((trip) {
                                final theme = Theme.of(context);
                                final isDark =
                                    theme.brightness == Brightness.dark;
                                final cardColor = isDark
                                    ? theme.colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.65)
                                    : const Color(0xFF1A1F2B);
                                final primaryText = isDark
                                    ? Colors.white
                                    : Colors.white;
                                final secondaryText = primaryText.withValues(
                                  alpha: 0.7,
                                );

                                final coverUrl = trip.coverMedia?.url;

                                return InkWell(
                                  borderRadius: BorderRadius.circular(12),
                                  onTap: () {
                                    context.push(
                                      '/trip/${trip.id}',
                                      extra: {'from': '/home'},
                                    );
                                  },
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: cardColor,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark
                                            ? theme.dividerColor.withValues(
                                                alpha: 0.35,
                                              )
                                            : Colors.white.withValues(
                                                alpha: 0.08,
                                              ),
                                      ),
                                      boxShadow: [
                                        if (!isDark)
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.25,
                                            ),
                                            blurRadius: 12,
                                            offset: const Offset(0, 5),
                                          ),
                                      ],
                                    ),
                                    child: Row(
                                      children: [
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          child: SizedBox(
                                            width: 64,
                                            height: 64,
                                            child: coverUrl != null
                                                ? Image.network(
                                                    buildOptimizedImageUrl(
                                                      coverUrl,
                                                      width: 480,
                                                      height: 480,
                                                    ),
                                                    fit: BoxFit.cover,
                                                    errorBuilder:
                                                        (
                                                          context,
                                                          error,
                                                          stackTrace,
                                                        ) {
                                                          return _buildRecentTripIcon(
                                                            primaryText,
                                                          );
                                                        },
                                                  )
                                                : _buildRecentTripIcon(
                                                    primaryText,
                                                  ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                trip.title,
                                                style: theme
                                                    .textTheme
                                                    .titleMedium
                                                    ?.copyWith(
                                                      color: primaryText,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                              if (trip.destinations.isNotEmpty)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                        top: 2.0,
                                                      ),
                                                  child: Text(
                                                    trip.destinations
                                                        .take(3)
                                                        .join(', '),
                                                    style: theme
                                                        .textTheme
                                                        .bodySmall
                                                        ?.copyWith(
                                                          color: secondaryText,
                                                        ),
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                  top: 6.0,
                                                ),
                                                child: Row(
                                                  children: [
                                                    Icon(
                                                      Icons.calendar_today,
                                                      size: 14,
                                                      color: secondaryText,
                                                    ),
                                                    const SizedBox(width: 6),
                                                    Expanded(
                                                      child: Text(
                                                        '${ProfileTab._formatDateForCard(trip.startDate)} - ${ProfileTab._formatDateForCard(trip.endDate)}',
                                                        style: theme
                                                            .textTheme
                                                            .bodySmall
                                                            ?.copyWith(
                                                              color:
                                                                  secondaryText,
                                                            ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Icon(
                                          Icons.chevron_right,
                                          color: secondaryText,
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                        ],
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String count,
    String label, {
    VoidCallback? onTap,
  }) {
    final content = Column(
      children: [
        Text(
          count,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: onTap != null ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        const SizedBox(height: 4),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
      ],
    );

    if (onTap == null) {
      return content;
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: content,
          ),
        ),
      ),
    );
  }

  Widget _buildRecentTripIcon(Color iconColor) {
    return Container(
      color: iconColor.withValues(alpha: 0.12),
      alignment: Alignment.center,
      child: Icon(Icons.travel_explore, color: iconColor, size: 28),
    );
  }
}
