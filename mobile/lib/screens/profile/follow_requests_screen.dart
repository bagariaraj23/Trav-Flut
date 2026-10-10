import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/user_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/follow_status.dart';
import 'package:tripthread/utils/app_feedback.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';

class FollowRequestsScreen extends StatefulWidget {
  const FollowRequestsScreen({super.key});

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

  Future<void> _handleAcceptRequest(
      String requestId, String followerName) async {
    if (!mounted) return;

    final userProvider = context.read<UserProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    
    final success = await userProvider.acceptFollowRequest(requestId);

    if (!mounted) return;

    if (success) {
      AppFeedback.showSuccess(
        context,
        'Accepted follow request from $followerName',
      );

      // Refresh follow requests list and current user's profile stats
      if (mounted && currentUserId != null) {
        await Future.wait([
          userProvider.loadPendingFollowRequests(),
          userProvider.loadProfileData(currentUserId, currentUserId),
        ]);
      }
    } else {
      AppFeedback.showError(
        context,
        userProvider.followRequestsError ?? 'Failed to accept request',
      );
    }
  }

  Future<void> _handleRejectRequest(
      String requestId, String followerName) async {
    if (!mounted) return;

    final userProvider = context.read<UserProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;
    
    final success = await userProvider.rejectFollowRequest(requestId);

    if (!mounted) return;

    if (success) {
      AppFeedback.showSuccess(
        context,
        'Rejected follow request from $followerName',
      );

      // Refresh follow requests list and current user's profile stats
      if (mounted && currentUserId != null) {
        await Future.wait([
          userProvider.loadPendingFollowRequests(),
          userProvider.loadProfileData(currentUserId, currentUserId),
        ]);
      }
    } else {
      AppFeedback.showError(
        context,
        userProvider.followRequestsError ?? 'Failed to reject request',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && context.mounted) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Follow Requests'),
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
      body: AppLayout.reading(
        context: context,
        child: Consumer<UserProvider>(
        builder: (context, userProvider, child) {
          if (userProvider.isFollowRequestsLoading &&
              userProvider.pendingFollowRequests.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (userProvider.followRequestsError != null) {
            return AppFeedback.error(
              context: context,
              title: 'Error loading requests',
              message: userProvider.followRequestsError!,
              onRetry: () => userProvider.loadPendingFollowRequests(),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Follow Requests',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When someone requests to follow you,\ntheir requests will appear here',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
      ),
      ),
    );
  }

  Widget _buildFollowRequestCard(
    BuildContext context,
    FollowRequestDto request,
    UserProvider userProvider,
  ) {
    final follower = request.follower;

    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
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
                  ChatAvatar(
                    radius: 25,
                    avatarUrl: follower.avatarUrl,
                    username: follower.username,
                    name: follower.name,
                  ),

                  const SizedBox(width: 16),

                  // User Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          follower.name ?? 'User',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (follower.username != null)
                          Text(
                            follower.username!,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          _formatDateTime(request.createdAt),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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
                      onPressed:
                          userProvider.isProcessingRequestId == request.id
                              ? null
                              : () => _handleRejectRequest(
                                    request.id,
                                    follower.name ?? 'User',
                                  ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                      ),
                      child: userProvider.isProcessingRequestId == request.id &&
                              userProvider.followRequestActionIsAccept == false
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
                      onPressed:
                          userProvider.isProcessingRequestId == request.id
                              ? null
                              : () => _handleAcceptRequest(
                                    request.id,
                                    follower.name ?? 'User',
                                  ),
                      child: userProvider.isProcessingRequestId == request.id &&
                              userProvider.followRequestActionIsAccept == true
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
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
