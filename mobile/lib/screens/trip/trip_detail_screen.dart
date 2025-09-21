import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/widgets/loading_button.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;

  const TripDetailScreen({
    Key? key,
    required this.tripId,
  }) : super(key: key);

  @override
  State<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends State<TripDetailScreen> {
  Trip? _trip;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  Future<void> _loadTrip() async {
    final tripProvider = context.read<TripProvider>();
    final trip = await tripProvider.getTrip(widget.tripId);

    if (mounted) {
      setState(() {
        _trip = trip;
        _isLoading = false;
      });
    }
  }

  Future<void> _endTrip() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('End Trip'),
        content: const Text(
            'Are you sure you want to end this trip? This will generate your final post.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('End Trip'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final tripProvider = context.read<TripProvider>();
      final success = await tripProvider.endTrip();

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip ended successfully! 🎉')),
        );
        await _loadTrip(); // Reload to get updated trip
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Use a single, unified Scaffold for both success and error states.
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // This SliverAppBar is now ALWAYS part of the widget tree,
          // guaranteeing the back button is always visible.
          SliverAppBar(
            expandedHeight: 250,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  context.go('/home');
                }
              },
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                // The title changes based on whether the trip was found.
                _trip?.title ?? 'Trip Not Found',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  shadows: [
                    Shadow(
                      offset: Offset(0, 1),
                      blurRadius: 3,
                      color: Colors.black54,
                    ),
                  ],
                ),
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Conditionally show the trip's cover image or the default cover.
                  _trip?.coverMediaUrl != null
                      ? Image.network(
                          _trip!.coverMediaUrl!,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildDefaultCover();
                          },
                        )
                      : _buildDefaultCover(),
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withOpacity(0.7),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              // Actions are only built if the trip exists and meets the criteria.
              if (_trip != null &&
                  _trip!.userId ==
                      context.read<AuthProvider>().currentUser?.id &&
                  _trip!.status == TripStatus.ongoing)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: () {
                    context.go('/trip/${widget.tripId}/thread',
                        extra: {'from': '/trip/${widget.tripId}'});
                  },
                ),
            ],
          ),

          // --- CONDITIONAL BODY ---
          // We use a Sliver widget to place content in the scroll view.

          if (_trip == null)
            // If the trip is not found, show a centered error message
            // that fills the rest of the available screen space.
            SliverFillRemaining(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.grey[400],
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Trip Not Found',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'This trip may have been deleted or you may not have permission to view it.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            // If the trip IS found, show the normal trip content.
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTripInfoCard(),
                    const SizedBox(height: 16),
                    if (_trip!.userId ==
                        context.read<AuthProvider>().currentUser?.id)
                      _buildOwnerActions(),
                    const SizedBox(height: 16),
                    _buildThreadSection(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDefaultCover() {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(
          Icons.travel_explore,
          size: 80,
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildTripInfoCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status Badge
            Row(
              children: [
                _buildStatusBadge(_trip!.status),
                const Spacer(),
                if (_trip!.mood != null) _buildMoodChip(_trip!.mood!),
              ],
            ),

            const SizedBox(height: 12),

            // Destinations
            Row(
              children: [
                Icon(Icons.location_on, color: Colors.grey[600], size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _trip!.destinations.join(', '),
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                ),
              ],
            ),

            if (_trip!.description != null) ...[
              const SizedBox(height: 12),
              Text(
                _trip!.description!,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],

            const SizedBox(height: 12),

            // Dates
            if (_trip!.startDate != null || _trip!.endDate != null)
              Row(
                children: [
                  Icon(Icons.calendar_today, color: Colors.grey[600], size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _formatDateRange(_trip!.startDate, _trip!.endDate),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ),

            const SizedBox(height: 12),

            // Stats
            Row(
              children: [
                _buildStatItem(
                  Icons.photo_library,
                  '${_trip!.entryCount ?? 0}',
                  'Entries',
                ),
                const SizedBox(width: 24),
                _buildStatItem(
                  Icons.people,
                  '${_trip!.participantCount ?? 0}',
                  'Participants',
                ),
                if (_trip!.type != null) ...[
                  const SizedBox(width: 24),
                  _buildStatItem(
                    Icons.group,
                    _getTripTypeLabel(_trip!.type!),
                    'Type',
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOwnerActions() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Trip Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 12),
            if (_trip!.status == TripStatus.ongoing) ...[
              ElevatedButton.icon(
                onPressed: () {
                  context.go('/trip/${widget.tripId}/thread',
                      extra: {'from': '/trip/${widget.tripId}'});
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Entry'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  context.go('/trip/${widget.tripId}/participants',
                      extra: {'from': '/trip/${widget.tripId}'});
                },
                icon: const Icon(Icons.people),
                label: const Text('Manage Participants'),
              ),
              const SizedBox(height: 8),
              Consumer<TripProvider>(
                builder: (context, tripProvider, child) {
                  return LoadingButton(
                    onPressed: _endTrip,
                    isLoading: tripProvider.isLoading,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                    child: const Text('End Trip'),
                  );
                },
              ),
            ] else if (_trip!.status == TripStatus.ended &&
                _trip!.finalPost != null) ...[
              ElevatedButton.icon(
                onPressed: () {
                  // TODO: Navigate to final post screen
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text('Final post feature coming soon!')),
                  );
                },
                icon: const Icon(Icons.auto_awesome),
                label: const Text('View Final Post'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildThreadSection() {
    final entries = _trip!.threadEntries ?? [];

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'Trip Thread',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const Spacer(),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: () {
                      context.go('/trip/${widget.tripId}/thread',
                          extra: {'from': '/trip/${widget.tripId}'});
                    },
                    child: const Text('View All'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.timeline,
                      size: 48,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No entries yet',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start documenting your journey!',
                      style: TextStyle(
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              )
            else
              Column(
                children: entries.take(3).map((entry) {
                  return _buildThreadEntryPreview(entry);
                }).toList(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildThreadEntryPreview(TripThreadEntry entry) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEntryTypeIcon(entry.type),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.contentText != null)
                  Text(
                    entry.contentText!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (entry.locationName != null)
                  Text(
                    '📍 ${entry.locationName}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.primary,
                        ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _formatDateTime(entry.createdAt),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[600],
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTypeIcon(ThreadEntryType type) {
    IconData icon;
    Color color;

    switch (type) {
      case ThreadEntryType.text:
        icon = Icons.text_fields;
        color = Colors.blue;
        break;
      case ThreadEntryType.media:
        icon = Icons.photo_camera;
        color = Colors.green;
        break;
      case ThreadEntryType.location:
        icon = Icons.location_on;
        color = Colors.red;
        break;
      case ThreadEntryType.checkin:
        icon = Icons.check_circle;
        color = Colors.orange;
        break;
    }

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }

  Widget _buildStatusBadge(TripStatus status) {
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
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

  Widget _buildMoodChip(TripMood mood) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Text(
        '${_getTripMoodEmoji(mood)} ${_getTripMoodLabel(mood)}',
        style: TextStyle(
          color: Theme.of(context).colorScheme.onPrimaryContainer,
          fontWeight: FontWeight.w500,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String value, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey[600],
                    fontSize: 10,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  String _formatDateRange(DateTime? start, DateTime? end) {
    if (start == null && end == null) return 'Dates not set';
    if (start == null) return 'Until ${_formatDate(end!)}';
    if (end == null) return 'From ${_formatDate(start)}';
    return '${_formatDate(start)} - ${_formatDate(end)}';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
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

  String _getTripTypeLabel(TripType type) {
    switch (type) {
      case TripType.solo:
        return 'Solo';
      case TripType.group:
        return 'Group';
      case TripType.couple:
        return 'Couple';
      case TripType.family:
        return 'Family';
    }
  }

  String _getTripMoodLabel(TripMood mood) {
    switch (mood) {
      case TripMood.relaxed:
        return 'Relaxed';
      case TripMood.adventure:
        return 'Adventure';
      case TripMood.spiritual:
        return 'Spiritual';
      case TripMood.cultural:
        return 'Cultural';
      case TripMood.party:
        return 'Party';
      case TripMood.mixed:
        return 'Mixed';
    }
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
}
