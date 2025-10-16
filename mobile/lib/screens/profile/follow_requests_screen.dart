import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/follow_status.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({Key? key}) : super(key: key);

  @override
  State<FollowRequestsScreen> createState() => _FollowRequestsScreenState();
}

class _FollowRequestsScreenState extends State<FollowRequestsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<UserProvider>().loadPendingFollowRequests();
    });
  }

  Future<void> _handleAcceptRequest(String requestId, String followerName) async {
    if (!mounted) return;

    final userProvider = context.read<UserProvider>();
    final success = await userProvider.acceptFollowRequest(requestId);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Accepted follow request from $followerName'),
          backgroundColor: Colors.green,
        ),
      );

      // Refresh follow requests list
      if (mounted) {
        await userProvider.loadPendingFollowRequests();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userProvider.followRequestsError ?? 'Failed to accept request'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _handleRejectRequest(String requestId, String followerName) async {
    if (!mounted) return;

    final userProvider = context.read<UserProvider>();
    final success = await userProvider.rejectFollowRequest(requestId);

    if (!mounted) return;

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Rejected follow request from $followerName'),
          backgroundColor: Colors.orange,
        ),
      );

      // Refresh follow requests list
      if (mounted) {
        await userProvider.loadPendingFollowRequests();
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(userProvider.followRequestsError ?? 'Failed to reject request'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Follow Requests'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            // This is the standard and most reliable way to navigate back.
            // It preserves the state of the previous screen, including the selected tab.
            if (context.canPop()) {
              context.pop();
            } else {
              // This is a fallback in case there's no screen to pop to,
              // which is unlikely in this flow but good practice to have.
              context.go('/home');
            }
          },
        ),
      ),
      body: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          if (userProvider.isFollowRequestsLoading && userProvider.pendingFollowRequests.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (userProvider.followRequestsError != null) {
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
                    userProvider.followRequestsError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      userProvider.loadPendingFollowRequests();
                    },
                    child: const Text('Retry'),
                  ),
                ],
              ),
            );
          }

          if (userProvider.pendingFollowRequests.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.person_add_outlined,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Follow Requests',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.grey[600],
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When someone requests to follow you,\ntheir requests will appear here',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Colors.grey[500],
                        ),
                  ),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async {
              await userProvider.loadPendingFollowRequests();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: userProvider.pendingFollowRequests.length,
              itemBuilder: (context, index) {
                final request = userProvider.pendingFollowRequests[index];
                return _buildFollowRequestCard(context, request, userProvider);
              },
            ),
          );
        },
      ),
    );
  }

  Widget _buildFollowRequestCard(
    BuildContext context,
    FollowRequestDto request,
    UserProvider userProvider,
  ) {
    final follower = request.follower;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => context.push('/profile/${follower.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  // Avatar
                  CircleAvatar(
                    radius: 25,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    backgroundImage: follower.avatarUrl != null
                        ? NetworkImage(follower.avatarUrl!)
                        : null,
                    child: follower.avatarUrl == null
                        ? Text(
                            follower.name?.substring(0, 1).toUpperCase() ?? 'U',
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
                        Text(
                          follower.name ?? 'User',
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                        ),
                        if (follower.username != null)
                          Text(
                            '@${follower.username}',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDateTime(request.createdAt),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey[500],
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              if (follower.bio != null && follower.bio!.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  follower.bio!,
                  style: Theme.of(context).textTheme.bodyMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: userProvider.isProcessingRequestId == request.id
                          ? null
                          : () => _handleRejectRequest(
                                request.id,
                                follower.name ?? 'User',
                              ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: BorderSide(color: Colors.red[300]!),
                      ),
                      child: userProvider.isProcessingRequestId == request.id
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Reject'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: userProvider.isProcessingRequestId == request.id
                          ? null
                          : () => _handleAcceptRequest(
                                request.id,
                                follower.name ?? 'User',
                              ),
                      child: userProvider.isProcessingRequestId == request.id
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
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