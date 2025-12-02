import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/widgets/loading_button.dart';
import 'package:tripthread/services/media_service.dart';

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
  MediaService? _mediaService;
  bool _isUpdatingCover = false;
  double? _coverUploadProgress;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaService ??= context.read<MediaService>();
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
        await _loadTrip();
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
        body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight:
                MediaQuery.of(context).orientation == Orientation.landscape
                    ? 150
                    : 250,
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
              titlePadding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 16,
              ),
              title: Text(
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
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    onTap: _canEditCover && !_isUpdatingCover
                        ? _showCoverOptions
                        : null,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        () {
                          final coverUrl = _trip?.coverMedia?.url;
                          if (coverUrl == null) {
                            return _buildDefaultCover();
                          }
                          return Image.network(
                            buildOptimizedImageUrl(coverUrl, width: 2048),
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return _buildDefaultCover();
                            },
                          );
                        }(),
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
                  if (_isUpdatingCover)
                    Positioned.fill(
                      child: Container(
                        color: Colors.black45,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            SizedBox(
                              height: 56,
                              width: 56,
                              child: CircularProgressIndicator(
                                value: _coverUploadProgress != null
                                    ? _coverUploadProgress!.clamp(0.0, 1.0)
                                    : null,
                                valueColor:
                                    const AlwaysStoppedAnimation<Color>(
                                        Colors.white),
                              ),
                            ),
                            if (_coverUploadProgress != null)
                              Padding(
                                padding: const EdgeInsets.only(top: 12.0),
                                child: Text(
                                  '${(_coverUploadProgress!.clamp(0.0, 1.0) * 100).round()}%',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            const SizedBox(height: 12),
                            const Text(
                              'Updating cover photo...',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              if (_canEditCover)
                IconButton(
                  icon: const Icon(Icons.photo_camera_back_outlined),
                  tooltip: _trip?.coverMedia == null
                      ? 'Add Cover Photo'
                      : 'Change Cover Photo',
                  onPressed: _isUpdatingCover ? null : _showCoverOptions,
                ),
              if (_trip != null &&
                  _trip!.status == TripStatus.ongoing &&
                  _isOwnerOrParticipant())
                IconButton(
                  icon: const Icon(Icons.add),
                  tooltip: 'Add Entry',
                  onPressed: () {
                    context.push('/trip/${widget.tripId}/thread',
                        extra: {'from': '/trip/${widget.tripId}'});
                  },
                ),
            ],
          ),
          if (_trip == null)
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
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTripInfoCard(),
                    const SizedBox(height: 16),
                    if (_isOwnerOrParticipant())
                      _buildTripActions(),
                    const SizedBox(height: 16),
                    _buildThreadSection(),
                  ],
                ),
              ),
            ),
        ],
      ),
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

  bool get _canEditCover =>
      _trip != null &&
      _trip!.status == TripStatus.ongoing &&
      _isOwnerOrParticipant();

  void _showCoverOptions() {
    if (!_canEditCover || _isUpdatingCover) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from gallery'),
                onTap: () {
                  Navigator.of(context).pop();
                  _changeCover(fromCamera: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () {
                  Navigator.of(context).pop();
                  _changeCover(fromCamera: true);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _changeCover({required bool fromCamera}) async {
    final mediaService = _mediaService ?? context.read<MediaService>();
    try {
      final file = await mediaService.pickImage(fromCamera: fromCamera);
      if (file == null) return;

      if (!mounted) return;
      setState(() {
        _isUpdatingCover = true;
        _coverUploadProgress = 0.0;
      });

      final uploadedMedia = await mediaService.uploadMediaToCloudinary(
        file: file,
        tripId: widget.tripId,
        usage: 'trip_cover',
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _coverUploadProgress = progress;
          });
        },
      );

      if (uploadedMedia == null) {
        throw Exception('Upload failed');
      }

      final tripProvider = context.read<TripProvider>();
      final success = await tripProvider.updateTripCover(
        tripId: widget.tripId,
        coverMediaId: uploadedMedia.id,
        fallbackMedia: uploadedMedia,
      );

      if (!success) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              tripProvider.error ?? 'Failed to update cover photo',
            ),
          ),
        );
      } else {
        await _loadTrip();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trip cover updated')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to update cover photo: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUpdatingCover = false;
          _coverUploadProgress = null;
        });
      }
    }
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
                  '${_trip!.entryCount}',
                  'Entries',
                ),
                const SizedBox(width: 24),
                _buildStatItem(
                  Icons.people,
                  '${_trip!.participantCount}',
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

  bool _isOwner() {
    final currentUser = context.read<AuthProvider>().currentUser;
    return _trip != null && currentUser != null && _trip!.userId == currentUser.id;
  }

  bool _isParticipant() {
    final currentUser = context.read<AuthProvider>().currentUser;
    if (_trip == null || currentUser == null) return false;
    return _trip!.participants?.any((p) => p.userId == currentUser.id) == true;
  }

  bool _isOwnerOrParticipant() {
    return _isOwner() || _isParticipant();
  }

  Widget _buildTripActions() {
    final isOwner = _isOwner();
    
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
            ElevatedButton.icon(
              onPressed: () {
                context.push(
                  '/trip/${widget.tripId}/map',
                  extra: {
                    'tripTitle': _trip!.title,
                    'places': _trip!.placeVisits,
                  },
                );
              },
              icon: const Icon(Icons.map),
              label: const Text('View Trip Map'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 8),
            if (_trip!.status == TripStatus.ongoing) ...[
              ElevatedButton.icon(
                onPressed: () {
                  context.go('/trip/${widget.tripId}/thread',
                      extra: {'from': '/trip/${widget.tripId}'});
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Entry'),
              ),
              // Owner-only actions
              if (isOwner) ...[
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  onPressed: () {
                    context.push('/trip/${widget.tripId}/participants',
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
              ],
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaUrl = entry.media?.url;
    final hasMedia = entry.type == ThreadEntryType.media &&
        mediaUrl != null &&
        mediaUrl.isNotEmpty;

    final String? previewUrl = hasMedia ? mediaUrl : null;

    final cardColor = isDark
        ? theme.colorScheme.surfaceVariant.withOpacity(0.65)
        : const Color(0xFF12161D);
    final primaryTextColor =
        isDark ? theme.colorScheme.onSurface : Colors.white;
    final secondaryTextColor = primaryTextColor.withOpacity(0.7);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? theme.dividerColor.withOpacity(0.35)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withOpacity(0.35),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hasMedia && previewUrl != null)
            _buildThreadMediaThumbnail(previewUrl, entry.media?.type)
          else
            _buildEntryTypeIcon(
              entry.type,
              accentOverride: primaryTextColor,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.contentText != null &&
                    entry.contentText!.trim().isNotEmpty)
                  Text(
                    entry.contentText!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: primaryTextColor,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                if (entry.locationName != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Text(
                      '📍 ${entry.locationName}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: secondaryTextColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(top: 6.0),
                  child: Text(
                    _formatDateTime(entry.createdAt),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEntryTypeIcon(ThreadEntryType type,
      {Color? accentOverride, bool compact = false}) {
    IconData icon;
    Color accent;

    switch (type) {
      case ThreadEntryType.text:
        icon = Icons.text_fields;
        accent = accentOverride ?? Colors.blueAccent;
        break;
      case ThreadEntryType.media:
        icon = Icons.photo_camera;
        accent = accentOverride ?? Colors.lightGreenAccent.shade200;
        break;
      case ThreadEntryType.location:
        icon = Icons.location_on;
        accent = accentOverride ?? Colors.redAccent;
        break;
      case ThreadEntryType.checkin:
        icon = Icons.check_circle;
        accent = accentOverride ?? Colors.orangeAccent;
        break;
    }

    return Container(
      padding: EdgeInsets.all(compact ? 6 : 8),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: accentOverride != null ? accentOverride : accent,
        size: compact ? 16 : 20,
      ),
    );
  }

  Widget _buildThreadMediaThumbnail(String url, MediaType? type) {
    final isVideo = type == MediaType.video;
    final optimizedUrl = isVideo
        ? buildVideoThumbnailUrl(url, maxWidth: 480)
        : buildOptimizedImageUrl(url, width: 480);

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 72,
        height: 72,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.network(
              optimizedUrl,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[300],
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image,
                  color: Colors.grey[600],
                  size: 28,
                ),
              ),
            ),
            if (isVideo)
              Container(
                color: Colors.black38,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.play_circle_fill,
                  color: Colors.white,
                  size: 32,
                ),
              ),
          ],
        ),
      ),
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
