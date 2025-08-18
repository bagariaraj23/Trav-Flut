import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/models/user.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({Key? key}) : super(key: key);

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final ScrollController _receivedScrollController = ScrollController();
  final ScrollController _sentScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _receivedScrollController.addListener(_onReceivedScroll);
    _sentScrollController.addListener(_onSentScroll);

    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userProvider = context.read<UserProvider>();
      userProvider.fetchFollowRequests(type: 'received', refresh: true);
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _receivedScrollController.dispose();
    _sentScrollController.dispose();
    super.dispose();
  }

  void _onReceivedScroll() {
    if (_receivedScrollController.position.pixels >=
        _receivedScrollController.position.maxScrollExtent - 200) {
      final userProvider = context.read<UserProvider>();
      if (userProvider.hasMoreFollowRequests && !userProvider.isFollowRequestsLoading) {
        userProvider.fetchFollowRequests(type: 'received');
      }
    }
  }

  void _onSentScroll() {
    if (_sentScrollController.position.pixels >=
        _sentScrollController.position.maxScrollExtent - 200) {
      final userProvider = context.read<UserProvider>();
      if (userProvider.hasMoreFollowRequests && !userProvider.isFollowRequestsLoading) {
        userProvider.fetchFollowRequests(type: 'sent');
      }
    }
  }

  void _onTabChanged(int index) {
    final userProvider = context.read<UserProvider>();
    final type = index == 0 ? 'received' : 'sent';
    userProvider.fetchFollowRequests(type: type, refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow Requests'),
        bottom: TabBar(
          controller: _tabController,
          onTap: _onTabChanged,
          tabs: const [
            Tab(text: 'Received'),
            Tab(text: 'Sent'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildReceivedTab(),
          _buildSentTab(),
        ],
      ),
    );
  }

  Widget _buildReceivedTab() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        return RefreshIndicator(
          onRefresh: () async {
            await userProvider.fetchFollowRequests(type: 'received', refresh: true);
          },
          child: _buildRequestsList(
            scrollController: _receivedScrollController,
            requests: userProvider.followRequests,
            isLoading: userProvider.isFollowRequestsLoading,
            error: userProvider.followRequestsError,
            emptyMessage: 'No follow requests',
            emptySubtitle: 'When someone requests to follow you, they\'ll appear here',
            isReceived: true,
          ),
        );
      },
    );
  }

  Widget _buildSentTab() {
    return Consumer<UserProvider>(
      builder: (context, userProvider, child) {
        return RefreshIndicator(
          onRefresh: () async {
            await userProvider.fetchFollowRequests(type: 'sent', refresh: true);
          },
          child: _buildRequestsList(
            scrollController: _sentScrollController,
            requests: userProvider.followRequests,
            isLoading: userProvider.isFollowRequestsLoading,
            error: userProvider.followRequestsError,
            emptyMessage: 'No pending requests',
            emptySubtitle: 'Your follow requests to private accounts will appear here',
            isReceived: false,
          ),
        );
      },
    );
  }

  Widget _buildRequestsList({
    required ScrollController scrollController,
    required List<FollowRequest> requests,
    required bool isLoading,
    required String? error,
    required String emptyMessage,
    required String emptySubtitle,
    required bool isReceived,
  }) {
    if (requests.isEmpty && isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (requests.isEmpty && error == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              isReceived ? Icons.person_add_outlined : Icons.send_outlined,
              size: 64,
              color: Colors.grey,
            ),
            const SizedBox(height: 16),
            Text(
              emptyMessage,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              emptySubtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    if (error != null) {
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
              'Error loading requests',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.red[300],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                context.read<UserProvider>().fetchFollowRequests(
                  type: isReceived ? 'received' : 'sent',
                  refresh: true,
                );
              },
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: requests.length + 1,
      itemBuilder: (context, index) {
        if (index == requests.length) {
          // Loading indicator at the bottom
          if (isLoading) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          return const SizedBox.shrink();
        }

        final request = requests[index];
        return _buildRequestCard(request, isReceived);
      },
    );
  }

  Widget _buildRequestCard(FollowRequest request, bool isReceived) {
    final user = isReceived ? request.sender : request.receiver;
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            // Avatar
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.grey[200],
              ),
              child: user?.avatarUrl != null
                  ? ClipOval(
                      child: Image.network(
                        user!.avatarUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.person,
                            size: 25,
                            color: Colors.grey[600],
                          );
                        },
                      ),
                    )
                  : Icon(
                      Icons.person,
                      size: 25,
                      color: Colors.grey[600],
                    ),
            ),

            const SizedBox(width: 16),

            // User Info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user?.name ?? 'Unknown User',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 16,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '@${user?.username ?? 'unknown'}',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 14,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getTimeAgo(DateTime.parse(request.createdAt)),
                    style: TextStyle(
                      color: Colors.grey[500],
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),

            // Action Buttons
            if (isReceived) ...[
              const SizedBox(width: 12),
              Column(
                children: [
                  SizedBox(
                    width: 80,
                    child: ElevatedButton(
                      onPressed: () => _handleRequest(request.id, 'accept'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Accept',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 80,
                    child: OutlinedButton(
                      onPressed: () => _handleRequest(request.id, 'reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[700],
                        side: BorderSide(color: Colors.grey[300]!),
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: const Text(
                        'Reject',
                        style: TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              const SizedBox(width: 12),
              SizedBox(
                width: 80,
                child: OutlinedButton(
                  onPressed: () => _cancelRequest(request.id),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red[700],
                    side: BorderSide(color: Colors.red[300]!),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return '${difference.inDays ~/ 7}w ago';
    } else if (difference.inDays > 0) {
      return '${difference.inDays}d ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours}h ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes}m ago';
    } else {
      return 'Just now';
    }
  }

  Future<void> _handleRequest(String requestId, String action) async {
    final userProvider = context.read<UserProvider>();
    
    final success = await userProvider.respondToFollowRequest(requestId, action);
    
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              action == 'accept' 
                ? 'Follow request accepted' 
                : 'Follow request rejected'
            ),
            backgroundColor: action == 'accept' ? Colors.green : Colors.orange,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userProvider.error ?? 'Failed to respond to request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _cancelRequest(String requestId) async {
    final userProvider = context.read<UserProvider>();
    
    final success = await userProvider.cancelFollowRequest(requestId);
    
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Follow request cancelled'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(userProvider.error ?? 'Failed to cancel request'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}