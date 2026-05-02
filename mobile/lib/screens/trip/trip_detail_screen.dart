import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'package:tripthread/widgets/loading_button.dart';
import 'package:tripthread/widgets/mention_text.dart';
import 'package:tripthread/services/media_service.dart';

class TripDetailScreen extends StatefulWidget {
  final String tripId;

  const TripDetailScreen({super.key, required this.tripId});

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
          'Are you sure you want to end this trip? This will generate your final post.',
        ),
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
      final navigator = context;
      final messenger = ScaffoldMessenger.of(context);
      final success = await tripProvider.endTrip(tripId: widget.tripId);

      if (!mounted) return;
      if (success) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Trip ended successfully! 🎉')),
        );
        await _loadTrip();
        if (!mounted) return;
        navigator.go('/trip/${widget.tripId}/final-post');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return PopScope(
      canPop: GoRouter.of(context).canPop(),
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          // No route to pop to — navigate to home instead of exiting app.
          context.go('/home', extra: {'explicitHome': true});
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
                  // Always go to home with explicitHome to avoid redirect loop back to thread.
                  context.go('/home', extra: {'explicitHome': true});
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
                                  Colors.black.withValues(alpha: 0.7),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Floating avatar button in top right (only for other users' trips)
                    if (_trip?.user != null && !_isOwner())
                      Positioned(
                        top: MediaQuery.of(context).padding.top + 12,
                        right: 12,
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            onTap: () {
                              context.push('/profile/${_trip!.user!.id}');
                            },
                            customBorder: const CircleBorder(),
                            borderRadius: BorderRadius.circular(20),
                            child: Container(
                              padding: const EdgeInsets.all(1.5),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.white,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.15),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                    spreadRadius: 0,
                                  ),
                                ],
                              ),
                              child: CircleAvatar(
                                radius: 15,
                                backgroundColor: Theme.of(
                                  context,
                                ).colorScheme.primary,
                                backgroundImage: _trip!.user!.avatarUrl != null
                                    ? NetworkImage(_trip!.user!.avatarUrl!)
                                    : null,
                                child: _trip!.user!.avatarUrl == null
                                    ? Text(
                                        (_trip!.user!.name != null &&
                                                _trip!.user!.name!.isNotEmpty
                                            ? _trip!.user!.name!
                                                .substring(0, 1)
                                                .toUpperCase()
                                            : 'U'),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.white,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    if (_isUpdatingCover)
                      Positioned.fill(
                        child: Container(
                          color: Colors.black45,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(
                                height: 56,
                                width: 56,
                                child: CircularProgressIndicator(
                                  value: _coverUploadProgress?.clamp(0.0, 1.0),
                                  valueColor:
                                      const AlwaysStoppedAnimation<Color>(
                                        Colors.white,
                                      ),
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
                if (_trip != null &&
                    _trip!.status == TripStatus.ongoing &&
                    _isOwnerOrParticipant())
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add Entry',
                    onPressed: () {
                      context.push(
                        '/trip/${widget.tripId}/thread',
                        extra: {'from': '/trip/${widget.tripId}'},
                      );
                    },
                  ),
                if (_canEditCover)
                  IconButton(
                    icon: const Icon(Icons.photo_camera_back_outlined),
                    tooltip: _trip?.coverMedia == null
                        ? 'Add Cover Photo'
                        : 'Change Cover Photo',
                    onPressed: _isUpdatingCover ? null : _showCoverOptions,
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
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Trip Not Found',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'This trip may have been deleted or you may not have permission to view it.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
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
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildTripInfoCard(),
                      const SizedBox(height: 16),
                      if (_isOwnerOrParticipant()) _buildTripActions(),
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
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(Icons.travel_explore, size: 80, color: Colors.white),
      ),
    );
  }

  bool get _canEditCover =>
      _trip != null &&
      (_trip!.status == TripStatus.ongoing ||
          _trip!.status == TripStatus.ended) &&
      _isOwnerOrParticipant();

  void _showCoverOptions() {
    if (!_canEditCover || _isUpdatingCover) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return Material(
          color: theme.colorScheme.surface,
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildCoverOptionTile(
                  context: context,
                  icon: Icons.photo_library_outlined,
                  label: 'Choose from gallery',
                  onTap: () {
                    Navigator.of(context).pop();
                    _changeCover(fromCamera: false);
                  },
                ),
                _buildCoverOptionTile(
                  context: context,
                  icon: Icons.photo_camera_outlined,
                  label: 'Take a photo',
                  onTap: () {
                    Navigator.of(context).pop();
                    _changeCover(fromCamera: true);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildCoverOptionTile({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ListTile(
      leading: Icon(icon),
      title: Text(label),
      onTap: onTap,
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
      final messenger = ScaffoldMessenger.of(context);
      final tripId = widget.tripId;
      final success = await tripProvider.updateTripCover(
        tripId: tripId,
        coverMediaId: uploadedMedia.id,
        fallbackMedia: uploadedMedia,
      );
      
      if (!mounted) return;

      if (!success) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(tripProvider.error ?? 'Failed to update cover photo'),
          ),
        );
      } else {
        await _loadTrip();
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('Trip cover updated')),
        );
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
          mainAxisSize: MainAxisSize.min,
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
                Icon(
                  Icons.location_on,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    (_trip!.destinations).join(', '),
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
                Icon(
                  Icons.calendar_today,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  size: 20,
                ),
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
    return _trip != null &&
        currentUser != null &&
        _trip!.userId == currentUser.id;
  }

  bool _isParticipant() {
    final currentUser = context.read<AuthProvider>().currentUser;
    if (_trip == null || currentUser == null) return false;
    return _trip!.participants?.any((p) => p.userId == currentUser.id) == true;
  }

  bool _isOwnerOrParticipant() {
    return _isOwner() || _isParticipant();
  }

  Future<void> _leaveTripAsParticipant() async {
    final tripProvider = context.read<TripProvider>();
    final choice = await showDialog<_TripDetailLeaveChoice>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave trip?'),
        content: const Text(
          'You will be removed as a participant.\n\n'
          'Keep your thread entries visible to others on this trip, '
          'or remove all entries you posted? '
          '(Removing entries is only allowed while the trip is ongoing.)',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, _TripDetailLeaveChoice.cancel),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(ctx, _TripDetailLeaveChoice.keepEntries),
            child: const Text('Keep my entries'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () =>
                Navigator.pop(ctx, _TripDetailLeaveChoice.removeEntries),
            child: const Text('Remove my entries'),
          ),
        ],
      ),
    );

    if (choice == null || choice == _TripDetailLeaveChoice.cancel) {
      return;
    }

    final removeMyData = choice == _TripDetailLeaveChoice.removeEntries;
    final ok = await tripProvider.leaveTrip(
      widget.tripId,
      removeMyData: removeMyData,
    );

    if (!mounted) return;
    final err = tripProvider.error;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removeMyData
                ? 'You left the trip; your entries were removed.'
                : 'You left the trip.',
          ),
        ),
      );
      context.go('/trips');
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(err ?? 'Could not leave trip'),
        ),
      );
    }
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
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
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
            if (_trip!.status == TripStatus.upcoming &&
                _isOwnerOrParticipant()) ...[
              ElevatedButton.icon(
                onPressed: () {
                  context.push(
                    '/trip/${widget.tripId}/participants',
                    extra: {'from': '/trip/${widget.tripId}'},
                  );
                },
                icon: const Icon(Icons.people),
                label: Text(
                  isOwner ? 'Manage Participants' : 'View Participants',
                ),
              ),
              if (!isOwner && _isParticipant()) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _leaveTripAsParticipant,
                  icon: const Icon(Icons.logout),
                  label: const Text('Leave trip'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 8),
            ],
            if (_trip!.status == TripStatus.ongoing) ...[
              ElevatedButton.icon(
                onPressed: () {
                  context.go(
                    '/trip/${widget.tripId}/thread',
                    extra: {'from': '/trip/${widget.tripId}'},
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('Add Entry'),
              ),
              const SizedBox(height: 8),
              ElevatedButton.icon(
                onPressed: () {
                  context.push(
                    '/trip/${widget.tripId}/participants',
                    extra: {'from': '/trip/${widget.tripId}'},
                  );
                },
                icon: const Icon(Icons.people),
                label: Text(
                  isOwner ? 'Manage Participants' : 'View Participants',
                ),
              ),
              if (!isOwner && _isParticipant()) ...[
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _leaveTripAsParticipant,
                  icon: const Icon(Icons.logout),
                  label: const Text('Leave trip'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (isOwner) ...[
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
            ] else if (_trip!.status == TripStatus.ended) ...[
              if (_isOwnerOrParticipant()) ...[
                ElevatedButton.icon(
                  onPressed: () {
                    context.push(
                      '/trip/${widget.tripId}/participants',
                      extra: {'from': '/trip/${widget.tripId}'},
                    );
                  },
                  icon: const Icon(Icons.people),
                  label: Text(
                    isOwner ? 'Manage Participants' : 'View Participants',
                  ),
                ),
                if (!isOwner && _isParticipant()) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: _leaveTripAsParticipant,
                    icon: const Icon(Icons.logout),
                    label: const Text('Leave trip'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 8),
              ],
              if (isOwner)
                ElevatedButton.icon(
                  onPressed: () {
                    context.go('/trip/${widget.tripId}/final-post');
                  },
                  icon: const Icon(Icons.auto_awesome),
                  label: Text(
                    _trip!.finalPost != null
                        ? 'View Final Post'
                        : 'Create Final Post',
                  ),
                )
              else if (_trip!.finalPost != null && _isOwnerOrParticipant())
                ElevatedButton.icon(
                  onPressed: () {
                    context.go('/trip/${widget.tripId}/final-post');
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
          mainAxisSize: MainAxisSize.min,
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
                      context.go(
                        '/trip/${widget.tripId}/thread',
                        extra: {'from': '/trip/${widget.tripId}'},
                      );
                    },
                    child: const Text('View All'),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (entries.isEmpty)
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.timeline,
                      size: 48,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No entries yet',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Start documenting your journey!',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
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

  Map<String, String> _usernameToUserIdFromTagged(List<User>? tagged) {
    if (tagged == null || tagged.isEmpty) return {};
    final map = <String, String>{};
    for (final u in tagged) {
      if (u.username != null && u.username!.isNotEmpty) {
        map[u.username!] = u.id;
      }
    }
    return map;
  }

  Widget _buildThreadEntryPreview(TripThreadEntry entry) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mediaUrl = entry.media?.url;
    final hasMedia =
        entry.type == ThreadEntryType.media &&
        mediaUrl != null &&
        mediaUrl.isNotEmpty;

    final String? previewUrl = hasMedia ? mediaUrl : null;

    final cardColor = isDark
        ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65)
        : const Color(0xFF12161D);
    final primaryTextColor = isDark
        ? theme.colorScheme.onSurface
        : Colors.white;
    final secondaryTextColor = primaryTextColor.withValues(alpha: 0.7);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? theme.dividerColor.withValues(alpha: 0.35)
              : Colors.white.withValues(alpha: 0.08),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.35),
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
            _buildEntryTypeIcon(entry.type, accentOverride: primaryTextColor),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.contentText != null &&
                    entry.contentText!.trim().isNotEmpty)
                  MentionText(
                    text: entry.contentText!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: primaryTextColor,
                      fontWeight: FontWeight.w500,
                      height: 1.35,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    usernameToUserId: _usernameToUserIdFromTagged(entry.taggedUsers),
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

  Widget _buildEntryTypeIcon(
    ThreadEntryType type, {
    Color? accentOverride,
    bool compact = false,
  }) {
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
        color: accent.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        icon,
        color: accentOverride ?? accent,
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
                color: Theme.of(context).colorScheme.onSurface.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
                ),
                alignment: Alignment.center,
                child: Icon(
                  Icons.broken_image,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
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
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
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
        Icon(
          icon,
          size: 16,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 4),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
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
    // Extract only date components to avoid timezone issues
    final dateOnly = DateTime.utc(date.year, date.month, date.day);
    return '${dateOnly.day}/${dateOnly.month}/${dateOnly.year}';
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

enum _TripDetailLeaveChoice { cancel, keepEntries, removeEntries }
