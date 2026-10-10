import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/models/trip_join_request.dart';
import 'package:tripthread/utils/app_feedback.dart';
import 'package:tripthread/utils/app_layout.dart';
import 'package:tripthread/widgets/chat/chat_avatar.dart';

class TripInvitationsScreen extends StatefulWidget {
  const TripInvitationsScreen({super.key});

  @override
  State<TripInvitationsScreen> createState() => _TripInvitationsScreenState();
}

class _TripInvitationsScreenState extends State<TripInvitationsScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<TripProvider>().loadPendingTripInvitations();
    });
  }

  Future<void> _handleResponse(
      String inviteId, bool accept, String tripTitle) async {
    if (!mounted) return;

    final tripProvider = context.read<TripProvider>();
    final success =
        await tripProvider.respondToTripInvitation(inviteId, accept);

    if (!mounted) return;

    if (success) {
      AppFeedback.showSuccess(
        context,
        '${accept ? 'Accepted' : 'Rejected'} invitation for "$tripTitle"',
      );
    } else {
      AppFeedback.showError(
        context,
        tripProvider.tripInvitesError ?? 'Failed to respond to invitation',
      );
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
          title: const Text('Trip Invitations'),
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
        child: Consumer<TripProvider>(
        builder: (context, tripProvider, child) {
          if (tripProvider.isTripInvitesLoading &&
              tripProvider.pendingTripInvitations.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          if (tripProvider.tripInvitesError != null) {
            return AppFeedback.error(
              context: context,
              title: 'Error loading invitations',
              message: tripProvider.tripInvitesError!,
              onRetry: () => tripProvider.loadPendingTripInvitations(),
            );
          }

          if (tripProvider.pendingTripInvitations.isEmpty) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.mail_outline,
                    size: 64,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No Trip Invitations',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'When someone invites you to a trip,\nthey will appear here',
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
              await tripProvider.loadPendingTripInvitations();
            },
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: tripProvider.pendingTripInvitations.length,
              itemBuilder: (context, index) {
                final invite = tripProvider.pendingTripInvitations[index];
                return _buildInvitationCard(context, invite, tripProvider);
              },
            ),
          );
        },
      ),
      ),
      ),
    );
  }

  Widget _buildInvitationCard(
    BuildContext context,
    TripJoinRequest invite,
    TripProvider tripProvider,
  ) {
    final sender = invite.sender;
    final trip = invite.trip;

    if (sender == null || trip == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => context.push('/trip/${trip.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  // Sender Avatar
                  ChatAvatar(
                    radius: 25,
                    avatarUrl: sender.avatarUrl,
                    username: sender.username,
                    name: sender.name,
                  ),
                  const SizedBox(width: 16),
                  // Sender Info & Trip Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          sender.name ?? 'User',
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        if (sender.username != null)
                          Text(
                            '@${sender.username}',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        const SizedBox(height: 4),
                        Text(
                          'Invited you to: "${trip.title}"',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                  ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Trip details
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .onSurface
                      .withValues(
                        alpha: Theme.of(context).brightness == Brightness.dark
                            ? 0.08
                            : 0.04,
                      ),
                  borderRadius: BorderRadius.circular(8),
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
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.location_on,
                            size: 16,
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            trip.destinations.join(', '),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    if (trip.startDate != null) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.calendar_today,
                              size: 16,
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            _formatDateRange(trip.startDate, trip.endDate),
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed:
                          tripProvider.respondingTripInviteId == invite.id
                              ? null
                              : () => _handleResponse(invite.id, false, trip.title),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: scheme.error,
                        side: BorderSide(color: scheme.error.withValues(alpha: 0.5)),
                      ),
                      child: tripProvider.respondingTripInviteId == invite.id &&
                              tripProvider.respondingTripInviteAccept == false
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
                          tripProvider.respondingTripInviteId == invite.id
                              ? null
                              : () => _handleResponse(invite.id, true, trip.title),
                      child: tripProvider.respondingTripInviteId == invite.id &&
                              tripProvider.respondingTripInviteAccept == true
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

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return 'Dates not set';
    if (start == null) return 'Until ${_formatDate(end!)}';
    if (end == null) return 'From ${_formatDate(start)}';
    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatDate(DateTime date) {
    // Extract only date components to avoid timezone issues
    final dateOnly = DateTime.utc(date.year, date.month, date.day);
    return '${dateOnly.day}/${dateOnly.month}/${dateOnly.year}';
  }
}
