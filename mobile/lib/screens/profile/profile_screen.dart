import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  List<Trip> _profileTrips = [];
  bool _profileTripsLoading = false;
  String? _profileTripsError;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure providers are available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  // A single, reliable method to load all necessary data for the screen.
  Future<void> _loadInitialData() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser != null) {
      await context.read<UserProvider>().loadProfileData(
        widget.userId,
        authProvider.currentUser!.id,
      );
      await _loadProfileTrips();
    }
  }

  Future<void> _loadProfileTrips() async {
    if (!mounted) return;
    setState(() {
      _profileTripsLoading = true;
      _profileTripsError = null;
    });
    final res = await context.read<ApiService>().getTripsForUser(widget.userId);
    if (!mounted) return;
    setState(() {
      _profileTripsLoading = false;
      if (res.success && res.data != null) {
        _profileTrips = res.data!;
      } else {
        _profileTrips = [];
        _profileTripsError = res.error ?? 'Could not load trips';
      }
    });
  }

  // The refresh action now uses the same centralized method.
  Future<void> _refreshProfile() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser != null) {
      await context.read<UserProvider>().loadProfileData(
        widget.userId,
        authProvider.currentUser!.id,
      );
      await _loadProfileTrips();
    }
  }

  // The toggle logic is simplified to just call the provider.
  // The provider is now responsible for updating the state and notifying the UI.
  Future<void> _handleFollowToggle() async {
    final userProvider = context.read<UserProvider>();
    final authProvider = context.read<AuthProvider>();

    if (authProvider.currentUser == null) return;

    // Fetch fresh status before taking action
    await userProvider.fetchDetailedFollowStatus(widget.userId);
    final detailedStatus = userProvider.getDetailedFollowStatus(widget.userId);

    if (detailedStatus == null) {
      if (!mounted) return;
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
        widget.userId,
        currentUserId: authProvider.currentUser!.id,
      );
      // Use the message from the API response if available
      actionMessage = success
          ? (userProvider.error == null ? 'Successfully unfollowed user' : userProvider.error!)
          : (userProvider.error ?? 'Failed to unfollow user');
    } else if (detailedStatus.isRequestPending) {
      success = await userProvider.cancelFollowRequest(
        widget.userId,
        currentUserId: authProvider.currentUser!.id,
      );
      actionMessage = success
          ? 'Follow request cancelled'
          : (userProvider.error ?? 'Failed to cancel follow request');
    } else {
      success = await userProvider.sendFollowRequest(
        widget.userId,
        currentUserId: authProvider.currentUser!.id,
      );
      // Check the updated status to determine the correct message
      await userProvider.fetchDetailedFollowStatus(widget.userId);
      final updatedStatus = userProvider.getDetailedFollowStatus(widget.userId);
      if (success) {
        if (updatedStatus?.isFollowing == true) {
          // Public profile - now following
          actionMessage = 'Successfully following user';
        } else if (updatedStatus?.isRequestPending == true) {
          // Private profile - request sent
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

    // Show appropriate message regardless of success/failure
    final errorMessage = userProvider.error ?? 
        userProvider.followRequestsError ?? 
        'An error occurred';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? actionMessage : errorMessage,
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    // Force refresh of profile data to ensure UI is in sync (avatar, stats, trips section)
    if (success) {
      userProvider.invalidateUserCache(widget.userId);
      if (mounted) {
        await context.read<FeedProvider>().loadDiscoverTrips(refresh: true);
      }
      await userProvider.loadProfileData(
        widget.userId,
        authProvider.currentUser!.id,
      );
      await _loadProfileTrips();
    }
  }

  void _openAvatarFullScreen(BuildContext context, String imageUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Center(
              child: InteractiveViewer(
                minScale: 0.5,
                maxScale: 4,
                child: Image.network(imageUrl, fit: BoxFit.contain),
              ),
            ),
            Positioned(
              top: MediaQuery.of(ctx).padding.top + 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 28),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint(
      '[ProfileScreen] Build method called for userId: ${widget.userId}',
    );

    // Consumer2 listens to both Auth and User providers for state changes.
    return Consumer3<AuthProvider, UserProvider, TripProvider>(
      builder: (context, authProvider, userProvider, tripProvider, child) {
        final currentUser = authProvider.currentUser;
        final user = userProvider.getUser(widget.userId);
        final stats = userProvider.getUserStats(widget.userId);
        final detailedStatus = userProvider.getDetailedFollowStatus(
          widget.userId,
        );
        final isOwnProfile = currentUser?.id == widget.userId;

        // Display a loading indicator only if the main user data is not yet available.
        if (userProvider.isLoading && user == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        debugPrint('[ProfileScreen] Build - currentUserId: ${currentUser?.id}');
        debugPrint('[ProfileScreen] Build - widget.userId: ${widget.userId}');
        debugPrint('[ProfileScreen] Build - isOwnProfile: $isOwnProfile');
        debugPrint(
          '[ProfileScreen] Build - currentUser exists: ${currentUser != null}',
        );

        // Handle the case where the user could not be found.
        if (user == null) {
          return Scaffold(
            appBar: AppBar(),
            body: Center(child: Text(userProvider.error ?? 'User not found.')),
          );
        }

        debugPrint(
          '[ProfileScreen] isOwnProfile: $isOwnProfile (currentUserId: ${currentUser?.id})',
        );
        // debugPrint('[ProfileScreen] pendingRequests: ${}');

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            context.go('/home', extra: {'explicitHome': true});
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(user.username ?? 'Profile'),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () =>
                    context.go('/home', extra: {'explicitHome': true}),
              ),
              actions: _buildAppBarActions(
                context,
                isOwnProfile,
                userProvider
                    .pendingFollowRequests, // Data comes directly from the provider.
                tripProvider.pendingTripInvitations, // Add trip invitations
              ),
            ),
            body: RefreshIndicator(
              onRefresh: _refreshProfile,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    _buildProfileHeader(
                      context,
                      user,
                      stats,
                      isOwnProfile,
                      detailedStatus?.isFollowing ?? false,
                      detailedStatus?.isRequestPending ?? false,
                      userProvider
                          .isLoading, // Pass loading state for the button.
                    ),
                    const SizedBox(height: 24),
                    _buildTripsSection(context, user, isOwnProfile),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildAppBarActions(
    BuildContext context,
    bool isOwnProfile,
    List<dynamic> pendingRequests,
    List<dynamic> pendingTripInvitations,
  ) {
    // Show actions only on own profile (mail = trip invites, follow requests, settings).
    if (!isOwnProfile) {
      return [];
    }

    final tripInvitesAction = Stack(
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
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              child: Text(
                '${pendingTripInvitations.length}',
                style: const TextStyle(color: Colors.white, fontSize: 8),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );

    return [
      tripInvitesAction,
      Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            icon: const Icon(Icons.person_add_outlined),
            tooltip: 'Follow Requests',
            onPressed: () => context.push('/follow-requests'),
          ),
          if (pendingRequests.isNotEmpty)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(6),
                ),
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text(
                  '${pendingRequests.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      IconButton(
        icon: const Icon(Icons.settings_outlined),
        tooltip: 'Settings',
        onPressed: () => context.push('/settings'),
      ),
    ];
  }

  /// Single character for avatar fallback (name > username > 'U').
  String _avatarInitial(User user) {
    final name = user.name?.trim();
    if (name != null && name.isNotEmpty) return name.substring(0, 1).toUpperCase();
    final username = user.username?.trim();
    if (username != null && username.isNotEmpty) {
      return username.substring(0, 1).toUpperCase();
    }
    return 'U';
  }

  /// Subtitle style for username and bio (smaller, muted; works in light and dark).
  TextStyle _profileSubtitleStyle(BuildContext context) {
    return Theme.of(context).textTheme.bodySmall!.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 14,
        );
  }

  Widget _buildProfileHeader(
    BuildContext context,
    User user,
    UserStats? stats,
    bool isOwnProfile,
    bool isFollowing,
    bool isRequestPending,
    bool isLoading,
  ) {
    final hasUsername =
        user.username != null && user.username!.trim().isNotEmpty;
    final hasBio = user.bio != null && user.bio!.trim().isNotEmpty;
    final bioText = hasBio ? user.bio!.trim() : '';
    // ~40 chars per line at bodySmall; clamp so short bios stay compact, long ones get space
    const int maxBioLinesCap = 20;
    const int charsPerLine = 40;
    final int bioMaxLines = hasBio
        ? (bioText.length / charsPerLine).ceil().clamp(1, maxBioLinesCap)
        : 0;
    final subtitleStyle = _profileSubtitleStyle(context);

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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Profile photo (tappable to enlarge when a photo exists)
          Center(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: user.avatarUrl != null && user.avatarUrl!.isNotEmpty
                    ? () => _openAvatarFullScreen(context, user.avatarUrl!)
                    : null,
                child: CircleAvatar(
                  radius: 48,
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  backgroundImage: user.avatarUrl != null
                      ? NetworkImage(user.avatarUrl!)
                      : null,
                  child: user.avatarUrl == null
                      ? Text(
                          _avatarInitial(user),
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),

          const SizedBox(height: 20),

          // Name and privacy indicator (prominent)
          Center(
            child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  (user.name?.trim().isNotEmpty == true
                      ? user.name!.trim()
                      : (hasUsername ? '@${user.username!.trim()}' : 'User')),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                ),
              ),
              if (user.isPrivate) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.lock_outlined,
                  size: 20,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ],
          ),
          ),

          // Username
          if (hasUsername) ...[
            const SizedBox(height: 6),
            Text(
              '@${user.username!.trim()}',
              style: subtitleStyle,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              textAlign: TextAlign.center,
            ),
          ],

          // Bio (centered; height adapts to length)
          if (hasBio) ...[
            SizedBox(height: hasUsername ? 8 : 6),
            Center(
              child: Text(
                bioText,
                style: subtitleStyle.copyWith(height: 1.4),
                textAlign: TextAlign.center,
                maxLines: bioMaxLines,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],

          const SizedBox(height: 20),

          // Stats Row
          Builder(
            builder: (context) {
              debugPrint(
                '[ProfileScreen] Building stats row - stats: ${stats != null}, isOwnProfile: $isOwnProfile',
              );
              if (stats != null) {
                debugPrint(
                  '[ProfileScreen] Stats values - trips: ${stats.tripCount}, followers: ${stats.followerCount}, following: ${stats.followingCount}',
                );
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(
                      context,
                      stats.tripCount.toString(),
                      'Trips',
                    ),
                    _buildStatColumn(
                      context,
                      stats.followerCount.toString(),
                      'Followers',
                      onTap: () {
                        debugPrint(
                          '[ProfileScreen] Navigating to followers for user: ${widget.userId}, isOwnProfile: $isOwnProfile',
                        );
                        debugPrint(
                          '[ProfileScreen] Stats - followerCount: ${stats.followerCount}',
                        );
                        try {
                          context.push(
                            '/profile/${widget.userId}/followers',
                            extra: {'from': '/profile/${widget.userId}'},
                          );
                          debugPrint(
                            '[ProfileScreen] Navigation to followers successful',
                          );
                        } catch (e, stackTrace) {
                          debugPrint(
                            '[ProfileScreen] Navigation to followers failed: $e',
                          );
                          debugPrint(
                            '[ProfileScreen] Stack trace: $stackTrace',
                          );
                        }
                      },
                    ),
                    _buildStatColumn(
                      context,
                      stats.followingCount.toString(),
                      'Following',
                      onTap: () {
                        debugPrint(
                          '[ProfileScreen] Navigating to following for user: ${widget.userId}, isOwnProfile: $isOwnProfile',
                        );
                        debugPrint(
                          '[ProfileScreen] Stats - followingCount: ${stats.followingCount}',
                        );
                        try {
                          context.push(
                            '/profile/${widget.userId}/following',
                            extra: {'from': '/profile/${widget.userId}'},
                          );
                          debugPrint(
                            '[ProfileScreen] Navigation to following successful',
                          );
                        } catch (e, stackTrace) {
                          debugPrint(
                            '[ProfileScreen] Navigation to following failed: $e',
                          );
                          debugPrint(
                            '[ProfileScreen] Stack trace: $stackTrace',
                          );
                        }
                      },
                    ),
                  ],
                );
              } else {
                debugPrint(
                  '[ProfileScreen] Stats is null, showing placeholder',
                );
                // Show placeholder stats if not loaded yet
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildStatColumn(context, '0', 'Trips'),
                    _buildStatColumn(context, '0', 'Followers'),
                    _buildStatColumn(context, '0', 'Following'),
                  ],
                );
              }
            },
          ),

          const SizedBox(height: 20),

          // Action Buttons
          if (isOwnProfile)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  context.push(
                    '/edit-profile',
                    extra: {'from': '/profile/${widget.userId}'},
                  );
                },
                child: const Text('Edit Profile'),
              ),
            )
          else if (user.isPrivate && !isFollowing && !isRequestPending)
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.08
                              : 0.04,
                        ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(
                            alpha: Theme.of(context).brightness == Brightness.dark
                                ? 0.18
                                : 0.10,
                          ),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.lock_outlined,
                        size: 32,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This account is private',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.onSurface,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Follow to see their trips and posts',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color:
                              Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : _handleFollowToggle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('Send Follow Request'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: Consumer<UserProvider>(
                builder: (context, userProvider, child) {
                  final detailedStatus = userProvider.getDetailedFollowStatus(
                    widget.userId,
                  );
                  final actualIsFollowing =
                      detailedStatus?.isFollowing ?? false;
                  final actualIsRequestPending =
                      detailedStatus?.isRequestPending ?? false;
                  final isProcessing = userProvider.isLoading;

                  // Use OutlinedButton for following/requested states
                  if (actualIsFollowing || actualIsRequestPending) {
                    return OutlinedButton(
                      onPressed: isProcessing ? null : _handleFollowToggle,
                      style: OutlinedButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.onSurface,
                        backgroundColor: Theme.of(context)
                            .colorScheme
                            .onSurface
                            .withValues(
                              alpha:
                                  Theme.of(context).brightness == Brightness.dark
                                      ? 0.08
                                      : 0.04,
                            ),
                        side: BorderSide(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(
                                alpha: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.18
                                    : 0.10,
                              ),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: isProcessing
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              actualIsFollowing ? 'Unfollow' : 'Cancel Request',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    );
                  }

                  // Use ElevatedButton for follow state
                  return ElevatedButton(
                    onPressed: isProcessing ? null : _handleFollowToggle,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: isProcessing
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                Colors.white,
                              ),
                            ),
                          )
                        : Text(
                            user.isPrivate ? 'Send Request' : 'Follow',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTripsSection(
    BuildContext context,
    User user,
    bool isOwnProfile,
  ) {
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
          Text(
            isOwnProfile ? 'Your Trips' : '${user.name}\'s Trips',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          if (_profileTripsLoading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_profileTripsError != null)
            Center(
              child: Text(
                _profileTripsError!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            )
          else if (_profileTrips.isEmpty)
            const Center(
              child: Column(
                children: [
                  Icon(Icons.map_outlined, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text(
                    'No trips yet',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _profileTrips.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final trip = _profileTrips[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.map_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    trip.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    trip.status.name,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    context.push(
                      '/trip/${trip.id}',
                      extra: {'from': '/profile/${widget.userId}'},
                    );
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatColumn(
    BuildContext context,
    String count,
    String label, {
    VoidCallback? onTap,
  }) {
    debugPrint(
      '[ProfileScreen] _buildStatColumn - label: $label, count: $count, onTap: ${onTap != null}',
    );

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            count,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: onTap != null
                  ? Theme.of(context).colorScheme.primary
                  : null,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return content;
    }

    void tapHandler() {
      debugPrint(
        '[ProfileScreen] StatColumn tapped - label: $label, count: $count',
      );
      try {
        onTap();
        debugPrint('[ProfileScreen] StatColumn onTap executed successfully');
      } catch (e, stackTrace) {
        debugPrint('[ProfileScreen] StatColumn onTap error: $e');
        debugPrint('[ProfileScreen] Stack trace: $stackTrace');
      }
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: tapHandler,
          borderRadius: BorderRadius.circular(8),
          child: content,
        ),
      ),
    );
  }
}
