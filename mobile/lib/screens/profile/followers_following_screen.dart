import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';

class FollowersFollowingScreen extends StatefulWidget {
  final String userId;
  final bool showFollowers; // true for followers, false for following

  const FollowersFollowingScreen({
    super.key,
    required this.userId,
    required this.showFollowers,
  });

  @override
  State<FollowersFollowingScreen> createState() =>
      _FollowersFollowingScreenState();
}

class _FollowersFollowingScreenState extends State<FollowersFollowingScreen> {
  final ScrollController _scrollController = ScrollController();
  ApiService? _apiService;
  List<User> _users = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _currentPage = 1;
  String? _error;
  final int _pageSize = 20;
  bool _initialLoadDone = false;
  String? _unfollowingUserId; // Track which user is being unfollowed

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    debugPrint('[FollowersFollowingScreen] initState - showFollowers: ${widget.showFollowers}, userId: ${widget.userId}');
    // Try to get ApiService early if possible
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        try {
          final apiService = context.read<ApiService>();
          if (_apiService == null) {
            _apiService = apiService;
            debugPrint('[FollowersFollowingScreen] initState postFrame - ApiService obtained');
          }
          if (!_initialLoadDone && _apiService != null) {
            _initialLoadDone = true;
            debugPrint('[FollowersFollowingScreen] initState postFrame - Starting load');
            _loadUsers();
          }
        } catch (e) {
          debugPrint('[FollowersFollowingScreen] initState postFrame - Error: $e');
        }
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_apiService == null) {
      try {
        _apiService = context.read<ApiService>();
        debugPrint('[FollowersFollowingScreen] ApiService obtained from context');
      } catch (e) {
        debugPrint('[FollowersFollowingScreen] Error getting ApiService: $e');
      }
    }
    
    if (!_initialLoadDone && _apiService != null) {
      _initialLoadDone = true;
      debugPrint('[FollowersFollowingScreen] Initializing, loading ${widget.showFollowers ? 'followers' : 'following'} for user: ${widget.userId}');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _loadUsers();
        }
      });
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 200 &&
        !_isLoading &&
        _hasMore) {
      _loadMoreUsers();
    }
  }

  Future<void> _loadUsers({bool refresh = false}) async {
    if (_isLoading || _apiService == null) {
      debugPrint('[FollowersFollowingScreen] Skipping load - isLoading: $_isLoading, apiService: ${_apiService != null}');
      return;
    }

    debugPrint('[FollowersFollowingScreen] Loading ${widget.showFollowers ? 'followers' : 'following'} - page: $_currentPage, refresh: $refresh');

    setState(() {
      _isLoading = true;
      _error = null;
      if (refresh) {
        _currentPage = 1;
        _users = [];
        _hasMore = true;
      }
    });

    try {
      debugPrint('[FollowersFollowingScreen] Making API call...');
      final response = widget.showFollowers
          ? await _apiService!.getFollowers(
              widget.userId,
              page: _currentPage,
              limit: _pageSize,
            )
          : await _apiService!.getFollowing(
              widget.userId,
              page: _currentPage,
              limit: _pageSize,
            );
      
      debugPrint('[FollowersFollowingScreen] API response - success: ${response.success}, data: ${response.data != null}');
      if (response.data != null) {
        debugPrint('[FollowersFollowingScreen] Response data - users: ${response.data!.users.length}, pagination: ${response.data!.pagination.total}');
      }

      if (response.success && response.data != null) {
        final usersList = response.data!.users;
        debugPrint('[FollowersFollowingScreen] Loaded ${usersList.length} ${widget.showFollowers ? 'followers' : 'following'}');
        if (mounted) {
          setState(() {
            _users.addAll(usersList);
            _hasMore = response.data!.pagination.page <
                response.data!.pagination.totalPages;
            _currentPage++;
            _isLoading = false;
            // Clear any previous errors
            _error = null;
          });
          debugPrint('[FollowersFollowingScreen] State updated - users: ${_users.length}, isLoading: false');
        }
      } else {
        debugPrint('[FollowersFollowingScreen] Error: ${response.error}');
        if (mounted) {
          setState(() {
            _error = response.error ?? 'Failed to load ${widget.showFollowers ? 'followers' : 'following'}';
            _isLoading = false;
          });
        }
      }
    } catch (e, stackTrace) {
      debugPrint('[FollowersFollowingScreen] Exception loading users: $e');
      debugPrint('[FollowersFollowingScreen] Stack trace: $stackTrace');
      setState(() {
        _error = 'An error occurred: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMoreUsers() async {
    if (!_hasMore || _isLoading) return;
    await _loadUsers();
  }

  Future<void> _refresh() async {
    await _loadUsers(refresh: true);
  }

  Widget _buildBody() {
    debugPrint('[FollowersFollowingScreen] _buildBody - error: $_error, users: ${_users.length}, isLoading: $_isLoading');
    
    // Show error state
    if (_error != null && _users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                _error!,
                style: TextStyle(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _refresh,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }
    
    // Show loading state
    if (_users.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Show empty state
    if (_users.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.showFollowers
                    ? Icons.people_outline
                    : Icons.person_outline,
                size: 64,
                color: Colors.grey[400],
              ),
              const SizedBox(height: 16),
              Text(
                widget.showFollowers
                    ? 'No followers yet'
                    : 'Not following anyone yet',
                style: TextStyle(
                  fontSize: 18,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                widget.showFollowers
                    ? 'When someone follows you, they\'ll appear here'
                    : 'Start following people to see them here',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
    
    // Show list of users
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(8),
      itemCount: _users.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _users.length) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final user = _users[index];
        return _buildUserTile(user);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('[FollowersFollowingScreen] build called - isLoading: $_isLoading, users: ${_users.length}, error: $_error, initialLoadDone: $_initialLoadDone');
    
    // Ensure ApiService is available
    if (_apiService == null) {
      try {
        _apiService = context.read<ApiService>();
        debugPrint('[FollowersFollowingScreen] build - ApiService obtained');
      } catch (e) {
        debugPrint('[FollowersFollowingScreen] build - Error getting ApiService: $e');
        // If we can't get ApiService, show error immediately
        if (_error == null && _users.isEmpty && !_isLoading) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _error = 'Unable to load ${widget.showFollowers ? 'followers' : 'following'}. Please try again.';
                _isLoading = false;
              });
            }
          });
        }
      }
    }
    
    // Ensure initial load happens if it hasn't yet
    if (!_initialLoadDone && _apiService != null && !_isLoading) {
      _initialLoadDone = true;
      debugPrint('[FollowersFollowingScreen] build - Triggering initial load');
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isLoading) {
          _loadUsers();
        }
      });
    }
    
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
          title: Text(widget.showFollowers ? 'Followers' : 'Following'),
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
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: _buildBody(),
        ),
      ),
    );
  }

  Widget _buildUserTile(User user) {
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    final isOwnProfile = currentUserId == widget.userId;
    final isFollowingList = !widget.showFollowers;
    final showUnfollowButton = isOwnProfile && isFollowingList;
    final isUnfollowing = _unfollowingUserId == user.id;

    return Card(
      margin: const EdgeInsets.only(bottom: 8, left: 8, right: 8),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          context.push('/profile/${user.id}');
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Theme.of(context).colorScheme.primary,
                backgroundImage:
                    user.avatarUrl != null ? NetworkImage(user.avatarUrl!) : null,
                child: user.avatarUrl == null
                    ? Text(
                        (user.name ?? user.username ?? 'U')
                            .substring(0, 1)
                            .toUpperCase(),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            user.name ?? 'No name',
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
                        if (user.isPrivate)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange[100],
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.orange[300]!),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.lock_outline,
                                  size: 11,
                                  color: Colors.orange[700],
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  'Private',
                                  style: TextStyle(
                                    color: Colors.orange[700],
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                    if (user.username != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        '@${user.username}',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.grey[600],
                            ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ],
                    if (user.bio != null && user.bio!.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        user.bio!,
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
              if (showUnfollowButton) ...[
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: isUnfollowing
                      ? null
                      : () => _handleUnfollow(user.id, currentUserId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    backgroundColor: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(
                          alpha: Theme.of(context).brightness == Brightness.dark
                              ? 0.08
                              : 0.04,
                        ),
                    side: BorderSide(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(
                            alpha: Theme.of(context).brightness == Brightness.dark
                                ? 0.18
                                : 0.10,
                          ),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    minimumSize: const Size(0, 32),
                  ),
                  child: isUnfollowing
                      ? const SizedBox(
                          height: 14,
                          width: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text(
                          'Unfollow',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleUnfollow(String userId, String? currentUserId) async {
    if (currentUserId == null) return;

    setState(() {
      _unfollowingUserId = userId;
    });

    try {
      final userProvider = context.read<UserProvider>();
      final success = await userProvider.unfollowUser(
        userId,
        currentUserId: currentUserId,
      );

      if (!mounted) return;

      if (success) {
        // Remove user from the list immediately
        setState(() {
          _users.removeWhere((u) => u.id == userId);
          _unfollowingUserId = null;
        });

        // Refresh the following count in the profile
        await userProvider.fetchUserStats(widget.userId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully unfollowed user'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        setState(() {
          _unfollowingUserId = null;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userProvider.error ?? 'Failed to unfollow user'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _unfollowingUserId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

