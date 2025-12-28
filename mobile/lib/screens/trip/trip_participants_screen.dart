import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/api_service.dart';

class TripParticipantsScreen extends StatefulWidget {
  final String tripId;

  const TripParticipantsScreen({super.key, required this.tripId});

  @override
  State<TripParticipantsScreen> createState() => _TripParticipantsScreenState();
}

class _TripParticipantsScreenState extends State<TripParticipantsScreen> {
  final _searchController = TextEditingController();
  Timer? _debounceTimer;
  List<TripParticipant> _participants = [];
  List<Map<String, dynamic>> _searchResults = [];
  bool _isSearching = false;
  @override
  void initState() {
    super.initState();
    _loadParticipants();
    _loadSentInvitations();
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    _debounceTimer?.cancel();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }
    setState(() {
      _isSearching = true;
    });
    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      final apiService = context.read<ApiService>();
      final response = await apiService.searchUsers(search: query, limit: 10);
      if (!mounted) return;
      if (response.success && response.data != null) {
        setState(() {
          _searchResults = response.data!;
          _isSearching = false;
        });
      } else {
        setState(() {
          _searchResults = [];
          _isSearching = false;
        });
      }
    });
  }

  Future<void> _loadSentInvitations() async {
    try {
      final tripProvider = context.read<TripProvider>();
      await tripProvider.loadSentTripInvitations(widget.tripId);
    } catch (e) {
      debugPrint('Failed to load sent invitations: $e');
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadParticipants() async {
    try {
      setState(() {});

      final apiService = context.read<ApiService>();
      final response = await apiService.getTripParticipants(widget.tripId);

      if (mounted) {
        setState(() {
          _participants = response;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _sendInvitation(String receiverId) async {
    try {
      final tripProvider = context.read<TripProvider>();
      final success = await tripProvider.sendTripInvitation(
        widget.tripId,
        receiverId,
      );

      if (mounted) {
        if (success) {
          await tripProvider.loadSentTripInvitations(widget.tripId);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation sent successfully!')),
          );
        } else {
          final error = tripProvider.error ?? '';
          if (error.contains('Unique constraint failed') ||
              error.contains('pending invitation')) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'User already has a pending invitation or is already a participant.',
                ),
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  error.isNotEmpty ? error : 'Failed to send invitation',
                ),
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Future<void> _cancelInvitation(String inviteId) async {
    try {
      final tripProvider = context.read<TripProvider>();
      final success = await tripProvider.cancelTripInvitation(
        widget.tripId,
        inviteId,
      );

      if (mounted) {
        if (success) {
          await tripProvider.loadSentTripInvitations(widget.tripId);
          setState(() {});
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Invitation cancelled successfully!')),
          );
        } else {
          final error = tripProvider.error ?? '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                error.isNotEmpty ? error : 'Failed to cancel invitation',
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  Widget _getInvitationButtonForSearch(String userId) {
    final tripProvider = context.watch<TripProvider>();
    final matchingInvitations = tripProvider.sentTripInvitations
        .where(
          (invitation) =>
              invitation.receiverId == userId &&
              invitation.tripId == widget.tripId,
        )
        .toList();

    if (matchingInvitations.isNotEmpty) {
      final invitation = matchingInvitations.first;
      return InkWell(
        onTap: tripProvider.isLoading
            ? null
            : () => _cancelInvitation(invitation.id),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.amber.shade200, width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.access_time, color: Colors.amber.shade700, size: 16),
              const SizedBox(width: 4),
              Text(
                'Pending',
                style: TextStyle(
                  color: Colors.amber.shade900,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return IconButton(
      onPressed: tripProvider.isLoading ? null : () => _sendInvitation(userId),
      icon: tripProvider.isLoading
          ? SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : const Icon(Icons.person_add),
      color: Theme.of(context).colorScheme.primary,
    );
  }

  Future<void> _removeParticipant(String userId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Participant'),
        content: const Text(
          'Are you sure you want to remove this participant from the trip?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final apiService = context.read<ApiService>();
        await apiService.removeTripParticipant(widget.tripId, userId);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Participant removed successfully!')),
          );
          await _loadParticipants();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to remove participant: ${e.toString()}'),
            ),
          );
        }
      }
    }
  }

  Widget _buildUserSearchResult(Map<String, dynamic> user) {
    final avatarUrl = user['avatarUrl'] as String?;
    final name = user['name'] ?? 'Unknown User';
    final username = user['username'] ?? 'No username';
    final userId = user['id'] as String;

    final isParticipant = _participants.any((p) => p.userId == userId);

    return Container(
      width: 200,
      margin: const EdgeInsets.only(right: 12),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: Theme.of(context).colorScheme.primary,
                backgroundImage: avatarUrl != null
                    ? NetworkImage(avatarUrl)
                    : null,
                child: avatarUrl == null
                    ? Icon(Icons.person, color: Colors.white, size: 20)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '@$username',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (isParticipant)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green.shade200, width: 1),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: Colors.green.shade700,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Member',
                        style: TextStyle(
                          color: Colors.green.shade900,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              else
                _getInvitationButtonForSearch(userId),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildParticipantTile(TripParticipant participant) {
    final currentUser = context.read<AuthProvider>().currentUser;
    final isOwner = participant.userId == currentUser?.id;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primary,
        backgroundImage: participant.user?.avatarUrl != null
            ? NetworkImage(participant.user!.avatarUrl!)
            : null,
        child: participant.user?.avatarUrl == null
            ? Icon(Icons.person, color: Colors.white, size: 20)
            : null,
      ),
      title: Text(
        participant.user?.name ?? 'Unknown User',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (participant.user?.username != null)
            Text('@${participant.user!.username}'),
          Text(
            'Role: ${participant.role}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
          Text(
            'Joined: ${_formatDate(participant.joinedAt)}',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ],
      ),
      trailing: isOwner
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Owner',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          : IconButton(
              onPressed: () => _removeParticipant(participant.userId),
              icon: const Icon(Icons.remove_circle_outline),
              color: Theme.of(context).colorScheme.error,
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvoked: (didPop) {
        if (!didPop) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/trip/${widget.tripId}');
          }
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: const Text('Manage Participants'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/trip/${widget.tripId}');
              }
            },
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              // Search Section
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Invite Participants',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        hintText: 'Search users by name or username...',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: _isSearching
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: Padding(
                                  padding: EdgeInsets.all(8.0),
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {
                                    _searchResults = [];
                                  });
                                },
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
              // Search Results and Participants List
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_searchResults.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Search Results',
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: _searchResults.length,
                                itemBuilder: (context, index) {
                                  final user = _searchResults[index];
                                  return _buildUserSearchResult(user);
                                },
                              ),
                            ],
                          ),
                        ),
                      // Participants List
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Current Participants',
                              style: Theme.of(context).textTheme.titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: _participants.length,
                              itemBuilder: (context, index) {
                                final participant = _participants[index];
                                return _buildParticipantTile(participant);
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Extract only date components to avoid timezone issues
    final dateOnly = DateTime.utc(date.year, date.month, date.day);
    return '${dateOnly.day}/${dateOnly.month}/${dateOnly.year}';
  }
}
