import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/models/user.dart';
import 'package:go_router/go_router.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;

  const ProfileScreen({super.key, required this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure providers are available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadInitialData();
    });
  }

  // A single, reliable method to load all necessary data for the screen.
  void _loadInitialData() {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser != null) {
      context.read<UserProvider>().loadProfileData(
        widget.userId,
        authProvider.currentUser!.id,
      );
    }
  }

  // The refresh action now uses the same centralized method.
  Future<void> _refreshProfile() async {
    final authProvider = context.read<AuthProvider>();
    if (authProvider.currentUser != null) {
      await context.read<UserProvider>().loadProfileData(
        widget.userId,
        authProvider.currentUser!.id,
      );
    }
  }

  // The toggle logic is simplified to just call the provider.
  // The provider is now responsible for updating the state and notifying the UI.
  Future<void> _handleFollowToggle() async {
    final userProvider = context.read<UserProvider>();
    final detailedStatus = userProvider.getDetailedFollowStatus(widget.userId);
    final authProvider = context.read<AuthProvider>();

    if (detailedStatus == null || authProvider.currentUser == null) return;

    bool success = false;
    String actionMessage = '';

    if (detailedStatus.isFollowing) {
      success = await userProvider.unfollowUser(
        widget.userId,
        currentUserId: authProvider.currentUser!.id,
      );
      actionMessage = success
          ? 'Successfully unfollowed user'
          : 'Failed to unfollow user';
    } else if (detailedStatus.isRequestPending) {
      success = await userProvider.cancelFollowRequest(
        widget.userId,
        currentUserId: authProvider.currentUser!.id,
      );
      actionMessage = success
          ? 'Follow request cancelled'
          : 'Failed to cancel follow request';
    } else {
      success = await userProvider.sendFollowRequest(
        widget.userId,
        currentUserId: authProvider.currentUser!.id,
      );
      actionMessage = success
          ? 'Follow request sent'
          : 'Failed to send follow request';
    }

    if (!mounted) return;

    // Show appropriate message regardless of success/failure
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success ? actionMessage : (userProvider.error ?? 'An error occurred'),
        ),
        backgroundColor: success ? Colors.green : Colors.red,
      ),
    );

    // Force refresh of profile data to ensure UI is in sync
    if (success) {
      await userProvider.loadProfileData(
        widget.userId,
        authProvider.currentUser!.id,
      );
    }
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
          canPop: true,
          onPopInvoked: (didPop) {
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
              title: Text(user.username ?? 'Profile'),
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
    if (!isOwnProfile) {
      return [];
    }

    return [
      // Trip Invitations Button
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
                constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
                child: Text(
                  '${pendingTripInvitations.length}',
                  style: const TextStyle(color: Colors.white, fontSize: 8),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
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

  Widget _buildProfileHeader(
    BuildContext context,
    User user,
    UserStats? stats,
    bool isOwnProfile,
    bool isFollowing,
    bool isRequestPending,
    bool isLoading,
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
        children: [
          // Avatar
          CircleAvatar(
            radius: 40,
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage: user.avatarUrl != null
                ? NetworkImage(user.avatarUrl!)
                : null,
            child: user.avatarUrl == null
                ? Text(
                    user.name?.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  )
                : null,
          ),

          const SizedBox(height: 16),

          // Name and Privacy Indicator
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  user.name ?? 'User',
                  style: Theme.of(context).textTheme.headlineMedium,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
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

          // Username
          if (user.username != null) ...[
            const SizedBox(height: 4),
            Text(
              '@${user.username}',
              style: Theme.of(context).textTheme.bodyMedium,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
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
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey[300]!),
                  ),
                  child: Column(
                    children: [
                      Icon(
                        Icons.lock_outlined,
                        size: 32,
                        color: Colors.black87,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This account is private',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: Colors.black87,
                            ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Follow to see their trips and posts',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[800],
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
                        foregroundColor: Colors.grey[900],
                        backgroundColor: Colors.grey[100],
                        side: BorderSide(color: Colors.grey[400]!),
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
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
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
