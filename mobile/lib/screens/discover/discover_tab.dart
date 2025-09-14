import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/feed_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:go_router/go_router.dart';

class DiscoverTab extends StatefulWidget {
  const DiscoverTab({super.key});

  @override
  State<DiscoverTab> createState() => _DiscoverTabState();
}

class _DiscoverTabState extends State<DiscoverTab> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final ScrollController _tripsScrollController = ScrollController();
  Timer? _debounceTimer;
  bool _isSearching = false;
  bool _showUserSearch = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _tripsScrollController.addListener(_onTripsScroll);
    _loadInitialTrips();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _tripsScrollController.dispose();
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _loadInitialTrips() {
    debugPrint('[DiscoverTab] Loading initial trips');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        debugPrint('[DiscoverTab] Calling loadDiscoverTrips with refresh=true');
        context.read<FeedProvider>().loadDiscoverTrips(refresh: true);
      }
    });
  }

  void _onSearchChanged(String query) {
    debugPrint('[DiscoverTab] Search query changed: "$query"');
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isSearching = true;
          _showUserSearch = query.isNotEmpty;
        });

        if (query.isNotEmpty) {
          debugPrint('[DiscoverTab] Searching for users with query: "$query"');
          // Search for users
          context.read<UserProvider>().searchUsers(
                search: query,
                refresh: true,
              );
        } else {
          debugPrint('[DiscoverTab] Empty query, clearing user search');
        }

        setState(() {
          _isSearching = false;
        });
      }
    });
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      debugPrint(
          '[DiscoverTab] Near end of user search scroll, checking for more users');
      final userProvider = context.read<UserProvider>();
      if (userProvider.hasMoreUsers && !userProvider.isDiscoverLoading) {
        debugPrint('[DiscoverTab] Loading more users');
        userProvider.searchUsers(
          search:
              _searchController.text.isEmpty ? null : _searchController.text,
        );
      } else {
        debugPrint('[DiscoverTab] No more users to load or already loading');
      }
    }
  }

  void _onTripsScroll() {
    if (_tripsScrollController.position.pixels >=
        _tripsScrollController.position.maxScrollExtent - 200) {
      debugPrint(
          '[DiscoverTab] Near end of trips scroll, checking for more trips');
      final feedProvider = context.read<FeedProvider>();
      if (feedProvider.hasMoreDiscoverTrips &&
          !feedProvider.isDiscoverTripsLoading) {
        debugPrint('[DiscoverTab] Loading more discover trips');
        feedProvider.loadDiscoverTrips();
      } else {
        debugPrint('[DiscoverTab] No more trips to load or already loading');
      }
    }
  }

  Future<void> _toggleFollow(String userId, bool isCurrentlyFollowing) async {
    final userProvider = context.read<UserProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    try {
      bool success = false;
      final detailedStatus = userProvider.getDetailedFollowStatus(userId);
      final isRequestPending = detailedStatus?.isRequestPending ?? false;

      if (isCurrentlyFollowing) {
        // Unfollow
        success = await userProvider.unfollowUser(userId,
            currentUserId: currentUserId);
      } else if (isRequestPending) {
        // Cancel follow request
        success = await userProvider.cancelFollowRequest(userId);
      } else {
        // Follow or send request
        success =
            await userProvider.followUser(userId, currentUserId: currentUserId);
      }

      if (!mounted) return;

      if (success) {
        // Only update local state if the action was successful
        final status = userProvider.getDetailedFollowStatus(userId);
        if (status != null) {
          final newState = status.isRequestPending
              ? 'requested to follow'
              : (status.isFollowing ? 'following' : 'not following');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Successfully ${newState} user'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else if (userProvider.error != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userProvider.error!),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Failed to ${isCurrentlyFollowing ? 'unfollow' : (userProvider.getDetailedFollowStatus(userId)?.isRequestPending == true ? 'cancel request' : 'follow')} user'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Discover'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Search Bar
          Container(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
              ),
              decoration: InputDecoration(
                hintText: 'Search users or trips...',
                hintStyle: const TextStyle(
                  color: Colors.grey,
                  fontSize: 16,
                ),
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _isSearching
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _showUserSearch = false;
                              });
                            },
                          )
                        : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                filled: true,
                fillColor: Colors.grey[100],
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Content based on search state
          Expanded(
            child: _showUserSearch
                ? _buildUserSearchResults()
                : _buildDiscoverTrips(),
          ),
        ],
      ),
    );
  }

  Widget _buildUserSearchResults() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        if (userProvider.discoverUsers.isEmpty &&
            userProvider.isDiscoverLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (userProvider.discoverUsers.isEmpty &&
            userProvider.discoverError == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.people_outline,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No users found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Try adjusting your search or check back later',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        if (userProvider.discoverError != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading users',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[300],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  userProvider.discoverError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    userProvider.clearDiscoverError();
                    userProvider.searchUsers(refresh: true);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            userProvider.searchUsers(refresh: true);
          },
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: userProvider.discoverUsers.length + 1,
            itemBuilder: (context, index) {
              if (index == userProvider.discoverUsers.length) {
                // Loading indicator at the bottom
                if (userProvider.isDiscoverLoading &&
                    userProvider.hasMoreUsers) {
                  return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }
                return const SizedBox.shrink();
              }

              final user = userProvider.discoverUsers[index];
              final isFollowing = user['isFollowing'] ?? false;
              final isFollowedBy = user['isFollowedBy'] ?? false;

              return _buildUserCard(context, user, isFollowing, isFollowedBy);
            },
          ),
        );
      },
    );
  }

  Widget _buildDiscoverTrips() {
    return Consumer<FeedProvider>(
      builder: (context, feedProvider, child) {
        if (feedProvider.discoverTrips.isEmpty &&
            feedProvider.isDiscoverTripsLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (feedProvider.discoverTrips.isEmpty &&
            feedProvider.discoverTripsError == null) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.explore_outlined,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'No trips to discover',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'Follow some travelers to see their amazing journeys',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),
          );
        }

        if (feedProvider.discoverTripsError != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red[300],
                ),
                const SizedBox(height: 16),
                Text(
                  'Error loading trips',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.red[300],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  feedProvider.discoverTripsError!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () {
                    feedProvider.clearDiscoverTripsError();
                    feedProvider.loadDiscoverTrips(refresh: true);
                  },
                  child: const Text('Retry'),
                ),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () async {
            feedProvider.loadDiscoverTrips(refresh: true);
          },
          child: GridView.builder(
            controller: _tripsScrollController,
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 0.8,
            ),
            itemCount: feedProvider.discoverTrips.length +
                (feedProvider.isDiscoverTripsLoading &&
                        feedProvider.hasMoreDiscoverTrips
                    ? 1
                    : 0),
            itemBuilder: (context, index) {
              if (index == feedProvider.discoverTrips.length) {
                // Loading indicator at the bottom
                return const Center(child: CircularProgressIndicator());
              }

              final trip = feedProvider.discoverTrips[index];
              return _buildDiscoverTripCard(context, trip);
            },
          ),
        );
      },
    );
  }

  Widget _buildDiscoverTripCard(BuildContext context, Trip trip) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.go('/trip/${trip.id}',
            extra: {'from': '/home', 'tab': 'discover'}),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.stretch, // Stretch children to fill width
          children: [
            // Cover image
            Expanded(
              flex: 5,
              child: SizedBox(
                width: double.infinity,
                child: trip.coverMediaUrl != null
                    ? Image.network(
                        trip.coverMediaUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return _buildTripPlaceholder(context, trip);
                        },
                      )
                    : _buildTripPlaceholder(context, trip),
              ),
            ),
            // Trip info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Top section: Status and Mood
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                          child:
                              _buildCompactStatusBadge(context, trip.status)),
                      if (trip.mood != null)
                        Flexible(
                          child: Text(
                            _getTripMoodEmoji(trip.mood!),
                            style: const TextStyle(fontSize: 16),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  // Title
                  if (trip.title.isNotEmpty)
                    Text(
                      trip.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 4),
                  // Destination
                  if (trip.destinations.isNotEmpty)
                    Text(
                      trip.destinations.first,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  const SizedBox(height: 8),
                  // Author info
                  if (trip.user != null)
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 10,
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          backgroundImage: trip.user!.avatarUrl != null
                              ? NetworkImage(trip.user!.avatarUrl!)
                              : null,
                          child: trip.user!.avatarUrl == null
                              ? Text(
                                  trip.user!.name
                                          ?.substring(0, 1)
                                          .toUpperCase() ??
                                      'U',
                                  style: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                )
                              : null,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            trip.user!.name ?? 'Unknown',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 12,
                                    ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
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

  Widget _buildTripPlaceholder(BuildContext context, Trip trip) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.7),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.travel_explore,
            size: 32,
            color: Colors.white,
          ),
          const SizedBox(height: 8),
          Text(
            trip.destinations.first,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildCompactStatusBadge(BuildContext context, TripStatus status) {
    Color color;
    String label;

    switch (status) {
      case TripStatus.upcoming:
        color = Colors.orange;
        label = 'Soon';
        break;
      case TripStatus.ongoing:
        color = Colors.green;
        label = 'Live';
        break;
      case TripStatus.ended:
        color = Colors.blue;
        label = 'Done';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }

  String _getTripMoodEmoji(TripMood mood) {
    switch (mood) {
      case TripMood.relaxed:
        return '😌';
      case TripMood.adventure:
        return '🏔️';
      case TripMood.spiritual:
        return '🧘';
      case TripMood.cultural:
        return '🏛️';
      case TripMood.party:
        return '🎉';
      case TripMood.mixed:
        return '🌈';
    }
  }

  Widget _buildUserCard(
    BuildContext context,
    Map<String, dynamic> user,
    bool isFollowing,
    bool isFollowedBy,
  ) {
    final username = user['username'] ?? 'No username';
    final name = user['name'] ?? 'No name';
    final bio = user['bio'];
    final avatarUrl = user['avatarUrl'];
    final isPrivate = user['isPrivate'] ?? false;
    final userId = user['id'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () => context.push('/profile/$userId'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 25,
                backgroundColor: Theme.of(context).colorScheme.primary,
                backgroundImage:
                    avatarUrl != null ? NetworkImage(avatarUrl) : null,
                child: avatarUrl == null
                    ? Text(
                        name.substring(0, 1).toUpperCase(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),

              const SizedBox(width: 16),

              // User Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            name,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                        if (isPrivate)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.orange[300]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 12,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Private',
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '@$username',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Colors.grey[600],
                                ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                    if (bio != null && bio.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        bio,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(width: 16),

              // Follow Button
              SizedBox(
                  width: 110,
                  child: Consumer<UserProvider>(
                      builder: (context, userProvider, child) {
                    final isProcessing =
                        userProvider.isProcessingRequestId == userId;
                    final detailedStatus =
                        userProvider.getDetailedFollowStatus(userId);
                    final isFollowing = detailedStatus?.isFollowing ??
                        false; // Get the latest state
                    final isRequestPending =
                        detailedStatus?.isRequestPending ?? false;
                    final isPrivate = detailedStatus?.isPrivate ?? false;

                    // STATE 1: Already following or request is pending (Use OutlinedButton)
                    if (isFollowing || isRequestPending) {
                      return OutlinedButton(
                        onPressed: isProcessing
                            ? null
                            : () => _toggleFollow(userId, isFollowing),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.grey[800],
                          backgroundColor: Colors.grey[100],
                          side: BorderSide(color: Colors.grey[300]!),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        child: isProcessing
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isFollowing ? 'Following' : 'Requested',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                      );
                    }

                    // STATE 2: Not following (Use ElevatedButton)
                    else {
                      return ElevatedButton(
                        onPressed: isProcessing
                            ? null
                            : () => _toggleFollow(userId, isFollowing),
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        child: isProcessing
                            ? const SizedBox(
                                height: 16,
                                width: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                      Colors.white),
                                ),
                              )
                            : FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isPrivate ? 'Request' : 'Follow',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                ),
                              ),
                      );
                    }
                  })),
            ],
          ),
        ),
      ),
    );
  }
}
