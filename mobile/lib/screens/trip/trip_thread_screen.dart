import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/widgets/map_picker_sheet.dart';
import 'package:tripthread/widgets/place_search_sheet.dart';
import 'package:tripthread/services/media_service.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';

const List<Color> _avatarColors = [
  Colors.orange,
  Colors.green,
  Colors.purple,
  Colors.teal,
  Colors.pink,
  Colors.indigo,
  Colors.brown,
  Colors.cyan,
  Colors.deepOrange,
  Colors.deepPurple,
  Colors.lime,
  Colors.amber,
];

Color _getAvatarColor(String userId, String currentUserId) {
  if (userId == currentUserId) {
    return Colors.blue;
  }
  final hash = userId.codeUnits.fold(0, (prev, c) => prev + c);
  return _avatarColors[hash % _avatarColors.length];
}

class TripThreadScreen extends StatefulWidget {
  final String tripId;

  const TripThreadScreen({
    Key? key,
    required this.tripId,
  }) : super(key: key);

  @override
  State<TripThreadScreen> createState() => _TripThreadScreenState();
}

class _TripThreadScreenState extends State<TripThreadScreen> {
  final _textController = TextEditingController();
  final _locationController = TextEditingController();
  final _scrollController = ScrollController();
  final _mediaService = MediaService();
  final _placeSearchScrollController = ScrollController();

  Trip? _trip;
  bool _isLoading = true;
  ThreadEntryType _selectedType = ThreadEntryType.text;
  File? _selectedMediaFile;
  bool _isUploadingMedia = false;
  Place? _selectedPlace;

  @override
  void initState() {
    super.initState();
    _loadTrip();
  }

  @override
  void dispose() {
    _textController.dispose();
    _locationController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadTrip() async {
    final tripProvider = context.read<TripProvider>();
    final trip = await tripProvider.getTrip(widget.tripId);

    if (mounted) {
      setState(() {
        _trip = trip;
        _isLoading = false;
      });

      if (trip != null) {
        await tripProvider.loadCurrentTripEntries(widget.tripId);
      }
    }
  }

  Future<void> _addEntry() async {
    final tripProvider = context.read<TripProvider>();
    bool success = false;

    switch (_selectedType) {
      case ThreadEntryType.text:
        if (_textController.text.trim().isNotEmpty) {
          success = await tripProvider.addTextEntry(_textController.text.trim(),
              tripId: widget.tripId);
          if (success) _textController.clear();
        }
        break;
      case ThreadEntryType.location:
        if (_selectedPlace != null) {
          debugPrint(
              '[TripThread] Adding location entry with placeId: ${_selectedPlace!.id}');

          success = await tripProvider.addThreadEntryWithPlace(
            tripId: widget.tripId,
            type: ThreadEntryType.location,
            contentText: _textController.text.trim().isNotEmpty
                ? _textController.text.trim()
                : null,
            placeId: _selectedPlace!.id,
          );
          if (success) {
            setState(() {
              _selectedPlace = null;
              _locationController.clear();
              _textController.clear();
            });
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(tripProvider.error ?? 'Failed to add location')),
            );
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a location first')),
          );
          return;
        }
        break;
      case ThreadEntryType.media:
        if (_selectedMediaFile != null) {
          setState(() {
            _isUploadingMedia = true;
          });

          try {
            final mediaUrl = "https://example.com/placeholder-media.jpg";
            success = await tripProvider.addMediaEntry(
              mediaUrl,
              caption: _textController.text.trim().isEmpty
                  ? null
                  : _textController.text.trim(),
              tripId: widget.tripId,
            );
            if (success) {
              _textController.clear();
              setState(() {
                _selectedMediaFile = null;
              });
            }
          } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to upload media: $e')),
            );
          } finally {
            setState(() {
              _isUploadingMedia = false;
            });
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Please select a media file first')),
          );
        }
        break;
      case ThreadEntryType.checkin:
        if (_selectedPlace != null) {
          success = await tripProvider.addThreadEntryWithPlace(
            tripId: widget.tripId,
            type: ThreadEntryType.checkin,
            contentText: _textController.text.trim().isNotEmpty
                ? _textController.text.trim()
                : null,
            placeId: _selectedPlace!.id,
          );
          if (success) {
            setState(() {
              _selectedPlace = null;
              _locationController.clear();
              _textController.clear();
            });
          }
        }
        break;
    }

    if (success) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            _scrollController.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    }
  }

  Future<void> _pickImage({bool fromCamera = false}) async {
    try {
      final file = await _mediaService.pickImage(fromCamera: fromCamera);
      if (file != null) {
        setState(() {
          _selectedMediaFile = file;
        });

        setState(() {
          _selectedType = ThreadEntryType.media;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final file = await _mediaService.pickVideo();
      if (file != null) {
        setState(() {
          _selectedMediaFile = file;
        });

        setState(() {
          _selectedType = ThreadEntryType.media;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking video: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_trip == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Trip Thread')),
        body: const Center(
          child: Text('Trip not found'),
        ),
      );
    }

    final currentUser = context.read<AuthProvider>().currentUser;
    final canAddEntries = _trip!.status == TripStatus.ongoing &&
        (currentUser?.id == _trip!.userId ||
            _trip!.participants?.any((p) => p.userId == currentUser?.id) ==
                true);

    return Scaffold(
      appBar: AppBar(
        title: Text(_trip?.title ?? 'Trip Thread'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            final extra = GoRouterState.of(context).extra;
            final from = (extra is Map && extra['from'] != null)
                ? extra['from'] as String
                : '/trip/${widget.tripId}';
            context.go(from);
          },
        ),
      ),
      body: Column(
        children: [
          // Thread entries
          Expanded(
            child: Consumer<TripProvider>(
              builder: (context, tripProvider, child) {
                final entries = tripProvider.currentTripEntries;

                if (entries.isEmpty) {
                  return CustomScrollView(
                    slivers: [
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(24),
                                  decoration: BoxDecoration(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primaryContainer
                                        .withOpacity(0.3),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(0.1),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    Icons.timeline,
                                    size: 64,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Text(
                                  'No entries yet',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface,
                                        fontWeight: FontWeight.w600,
                                      ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  canAddEntries
                                      ? 'Start documenting your journey!\nShare your experiences, photos, and locations.'
                                      : 'This trip has no entries yet.\nCheck back later for updates.',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurface
                                            .withOpacity(0.7),
                                        height: 1.5,
                                      ),
                                  textAlign: TextAlign.center,
                                ),
                                if (canAddEntries) ...[
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      ScaffoldMessenger.of(context)
                                          .showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                              'Ready to share! Start typing below.'),
                                          duration: Duration(seconds: 2),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.add),
                                    label: const Text('Add First Entry'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor:
                                          Theme.of(context).colorScheme.primary,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 24,
                                        vertical: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                return ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    return _buildThreadEntry(entries[index]);
                  },
                );
              },
            ),
          ),

          // Add entry section
          if (canAddEntries) _buildAddEntrySection(),
        ],
      ),
    );
  }

  Widget _buildThreadEntry(TripThreadEntry entry) {
    final isCurrentUser =
        context.read<AuthProvider>().currentUser?.id == entry.authorId;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Avatar
          Builder(
            builder: (context) {
              final currentUserId =
                  context.read<AuthProvider>().currentUser?.id;
              final avatarColor =
                  _getAvatarColor(entry.authorId, currentUserId ?? '');
              return CircleAvatar(
                radius: 18,
                backgroundColor: avatarColor,
                backgroundImage: entry.author.avatarUrl != null
                    ? NetworkImage(entry.author.avatarUrl!)
                    : null,
                child: entry.author.avatarUrl == null
                    ? Text(
                        entry.author.name?.substring(0, 1).toUpperCase() ?? 'U',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      )
                    : null,
              );
            },
          ),

          const SizedBox(width: 12),

          // Entry content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrentUser
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                    : Colors.grey[50],
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isCurrentUser
                      ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                      : Colors.grey[300]!,
                  width: 1.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isCurrentUser
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                        : Colors.black.withOpacity(0.04),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.author.name ?? 'User',
                          style:
                              Theme.of(context).textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isCurrentUser
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.black87,
                                  ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _buildEntryTypeIcon(entry.type),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _formatDateTime(entry.createdAt),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: isCurrentUser
                                        ? Theme.of(context)
                                            .colorScheme
                                            .primary
                                            .withOpacity(0.8)
                                        : Colors.grey[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Content
                  if (entry.contentText != null) ...[
                    Text(
                      entry.contentText!,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color:
                                isCurrentUser ? Colors.black87 : Colors.black87,
                            height: 1.5,
                          ),
                      overflow: TextOverflow.visible,
                      maxLines: null,
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Location card with theme colors
                  if (entry.type == ThreadEntryType.location ||
                      entry.locationName != null ||
                      entry.place != null ||
                      entry.gpsCoordinates != null)
                    GestureDetector(
                      onTap: () {
                        if (entry.place != null) {
                          context.push(
                            '/trip/${widget.tripId}/map',
                            extra: {
                              'tripTitle': _trip?.title ?? 'Trip Map',
                              'initialZoomLocation': entry.place,
                            },
                          );
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.only(top: 8),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red[50],
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.red[200]!,
                            width: 1.5,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Place name and icon
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color: Colors.red[100],
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    entry.type == ThreadEntryType.checkin
                                        ? Icons.check_circle
                                        : Icons.location_on,
                                    size: 18,
                                    color: Colors.red[700],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        entry.place?.name ??
                                            entry.locationName ??
                                            'Location',
                                        style: TextStyle(
                                          color: Colors.red[900],
                                          fontWeight: FontWeight.w600,
                                          fontSize: 14,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                      if (entry.place?.address != null)
                                        Text(
                                          entry.place!.address!,
                                          style: TextStyle(
                                            color: Colors.red[700]!
                                                .withOpacity(0.8),
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                          maxLines: 2,
                                        ),
                                    ],
                                  ),
                                ),
                                if (entry.place != null)
                                  IconButton(
                                    onPressed: () {
                                      context.push(
                                        '/trip/${widget.tripId}/map',
                                        extra: {
                                          'tripTitle':
                                              _trip?.title ?? 'Trip Map',
                                          'initialZoomLocation': entry.place,
                                        },
                                      );
                                    },
                                    icon: const Icon(Icons.map_outlined,
                                        size: 20),
                                    style: IconButton.styleFrom(
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(8),
                                      backgroundColor: Colors.red[100],
                                      foregroundColor: Colors.red[700],
                                    ),
                                  ),
                              ],
                            ),
                            // GPS coordinates
                            if ((entry.place?.lat != null &&
                                    entry.place?.lng != null) ||
                                entry.gpsCoordinates != null) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Icon(
                                    Icons.gps_fixed,
                                    size: 12,
                                    color: Colors.red[700]!.withOpacity(0.7),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    entry.place != null
                                        ? '${entry.place!.lat.toStringAsFixed(4)}, ${entry.place!.lng.toStringAsFixed(4)}'
                                        : '${entry.gpsCoordinates!.lat.toStringAsFixed(4)}, ${entry.gpsCoordinates!.lng.toStringAsFixed(4)}',
                                    style: TextStyle(
                                      color: Colors.red[700]!.withOpacity(0.8),
                                      fontSize: 11,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),

                  // Media display
                  if (entry.type == ThreadEntryType.media &&
                      entry.mediaUrl != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      constraints: const BoxConstraints(
                        maxHeight: 300,
                        minHeight: 150,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          entry.mediaUrl!,
                          fit: BoxFit.cover,
                          width: double.infinity,
                          loadingBuilder: (context, child, loadingProgress) {
                            if (loadingProgress == null) return child;
                            return Container(
                              height: 200,
                              child: Center(
                                child: CircularProgressIndicator(
                                  value: loadingProgress.expectedTotalBytes !=
                                          null
                                      ? loadingProgress.cumulativeBytesLoaded /
                                          loadingProgress.expectedTotalBytes!
                                      : null,
                                ),
                              ),
                            );
                          },
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              height: 150,
                              child: const Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.broken_image,
                                        size: 48, color: Colors.grey),
                                    SizedBox(height: 8),
                                    Text(
                                      'Failed to load image',
                                      style: TextStyle(color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // Tagged users
                  if (entry.taggedUsers != null &&
                      entry.taggedUsers!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 4,
                        runSpacing: 4,
                        children: entry.taggedUsers!.map((user) {
                          return Chip(
                            label: Text(
                              '@${user.username ?? user.name ?? 'User'}',
                              style: const TextStyle(fontSize: 12),
                              overflow: TextOverflow.ellipsis,
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer
                                .withOpacity(0.3),
                          );
                        }).toList(),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddEntrySection() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.5,
          ),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Entry type selector - Horizontally scrollable
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: ThreadEntryType.values.map((type) {
                        final isSelected = _selectedType == type;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: FilterChip(
                            label: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildEntryTypeIcon(type),
                                const SizedBox(width: 4),
                                Text(
                                  _getEntryTypeLabel(type),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                            selected: isSelected,
                            onSelected: (selected) {
                              setState(() {
                                _selectedType = type;
                              });
                            },
                            visualDensity: VisualDensity.compact,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        );
                      }).toList(),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // LOCATION SELECTOR - Made scrollable and more spacious
                  if (_selectedType == ThreadEntryType.location)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search field
                        InkWell(
                          onTap: () async {
                            final place = await showModalBottomSheet<Place>(
                              context: context,
                              isScrollControlled: true,
                              backgroundColor: Colors.transparent,
                              builder: (context) => PlaceSearchSheet(
                                controller: _placeSearchScrollController,
                              ),
                            );

                            if (place != null) {
                              setState(() {
                                _selectedPlace = place;
                                _locationController.text = place.name;
                              });
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.search, color: Colors.grey[600]),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: _selectedPlace != null
                                      ? Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _selectedPlace!.name,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w500,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            if (_selectedPlace!.address != null)
                                              Text(
                                                _selectedPlace!.address!,
                                                style: TextStyle(
                                                  color: Colors.grey[600],
                                                  fontSize: 12,
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                          ],
                                        )
                                      : Text(
                                          'Search for a location',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                ),
                                if (_selectedPlace != null)
                                  IconButton(
                                    icon: const Icon(Icons.close, size: 20),
                                    onPressed: () {
                                      setState(() {
                                        _selectedPlace = null;
                                        _locationController.clear();
                                      });
                                    },
                                    padding: const EdgeInsets.all(8),
                                    constraints: const BoxConstraints(),
                                    visualDensity: VisualDensity.compact,
                                  ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        // "OR" divider
                        Row(
                          children: [
                            Expanded(child: Divider(color: Colors.grey[300])),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16),
                              child: Text(
                                'OR',
                                style: TextStyle(
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            Expanded(child: Divider(color: Colors.grey[300])),
                          ],
                        ),

                        const SizedBox(height: 12),

                        // Map picker button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            icon: const Icon(Icons.map),
                            label: const Text('Pick on Map'),
                            onPressed: () async {
                              final place =
                                  await Navigator.of(context).push<Place>(
                                MaterialPageRoute(
                                  fullscreenDialog: true,
                                  builder: (context) => MapPickerModal(
                                    initialPlaceName: _selectedPlace?.name,
                                    initialLat: _selectedPlace?.lat,
                                    initialLng: _selectedPlace?.lng,
                                  ),
                                ),
                              );

                              if (place != null) {
                                setState(() {
                                  _selectedPlace = place;
                                  _locationController.text = place.name;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                      ],
                    ),

                  // MEDIA SELECTION - Made more compact
                  if (_selectedType == ThreadEntryType.media)
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey[300]!),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Media',
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(height: 12),
                          if (_selectedMediaFile != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    ['mp4', 'mov', 'avi'].contains(
                                            _selectedMediaFile!.path
                                                .split('.')
                                                .last
                                                .toLowerCase())
                                        ? Icons.video_file
                                        : Icons.image,
                                    color: Colors.grey[600],
                                    size: 24,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _selectedMediaFile!.path
                                              .split('/')
                                              .last,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w500,
                                            fontSize: 14,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        Text(
                                          '${(_selectedMediaFile!.lengthSync() / 1024 / 1024).toStringAsFixed(1)} MB',
                                          style: TextStyle(
                                            color: Colors.grey[600],
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: () {
                                      setState(() {
                                        _selectedMediaFile = null;
                                      });
                                    },
                                    icon: const Icon(Icons.close, size: 20),
                                    style: IconButton.styleFrom(
                                      backgroundColor: Colors.red[100],
                                      foregroundColor: Colors.red,
                                      visualDensity: VisualDensity.compact,
                                      padding: const EdgeInsets.all(8),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            // RESPONSIVE MEDIA BUTTONS
                            LayoutBuilder(
                              builder: (context, constraints) {
                                final isWide = constraints.maxWidth > 400;
                                if (isWide) {
                                  return Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _pickImage(fromCamera: false),
                                          icon: const Icon(Icons.photo_library,
                                              size: 18),
                                          label: const Text('Gallery'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () =>
                                              _pickImage(fromCamera: true),
                                          icon: const Icon(Icons.camera_alt,
                                              size: 18),
                                          label: const Text('Camera'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: _pickVideo,
                                          icon: const Icon(Icons.video_file,
                                              size: 18),
                                          label: const Text('Video'),
                                          style: OutlinedButton.styleFrom(
                                            padding: const EdgeInsets.symmetric(
                                              vertical: 10,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                }

                                // Narrow layout - Stack buttons vertically
                                return Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _pickImage(fromCamera: false),
                                            icon: const Icon(
                                                Icons.photo_library,
                                                size: 18),
                                            label: const Text('Gallery'),
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 10,
                                              ),
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () =>
                                                _pickImage(fromCamera: true),
                                            icon: const Icon(Icons.camera_alt,
                                                size: 18),
                                            label: const Text('Camera'),
                                            style: OutlinedButton.styleFrom(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                vertical: 10,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: OutlinedButton.icon(
                                        onPressed: _pickVideo,
                                        icon: const Icon(Icons.video_file,
                                            size: 18),
                                        label: const Text('Video'),
                                        style: OutlinedButton.styleFrom(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                        ],
                      ),
                    ),

                  // TEXT INPUT + SEND BUTTON - Compact and responsive
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _textController,
                          decoration: InputDecoration(
                            hintText: _getInputHint(),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            isDense: true,
                          ),
                          maxLines: 3,
                          minLines: 1,
                          textCapitalization: TextCapitalization.sentences,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Consumer<TripProvider>(
                        builder: (context, tripProvider, child) {
                          return IconButton(
                            onPressed: (tripProvider.isLoading ||
                                    _isUploadingMedia ||
                                    (_selectedType ==
                                            ThreadEntryType.location &&
                                        _selectedPlace == null))
                                ? null
                                : _addEntry,
                            icon: (tripProvider.isLoading || _isUploadingMedia)
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.send),
                            style: IconButton.styleFrom(
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.all(12),
                            ),
                          );
                        },
                      ),
                    ],
                  ),

                  // ERROR MESSAGE - Compact
                  Consumer<TripProvider>(
                    builder: (context, tripProvider, child) {
                      if (tripProvider.error != null) {
                        return Container(
                          margin: const EdgeInsets.only(top: 8),
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .error
                                .withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            tripProvider.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 12,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEntryTypeIcon(ThreadEntryType type) {
    IconData icon;
    Color color;

    switch (type) {
      case ThreadEntryType.text:
        icon = Icons.text_fields;
        color = Colors.blue[700]!; // Darker blue for better contrast
        break;
      case ThreadEntryType.media:
        icon = Icons.photo_camera;
        color = Colors
            .purple[700]!; // Changed from green to purple for better visibility
        break;
      case ThreadEntryType.location:
        icon = Icons.location_on;
        color = Colors.red[700]!; // Darker red for better contrast
        break;
      case ThreadEntryType.checkin:
        icon = Icons.check_circle;
        color = Colors.orange[700]!; // Darker orange for better contrast
        break;
    }

    return Icon(icon, color: color, size: 16);
  }

  String _getEntryTypeLabel(ThreadEntryType type) {
    switch (type) {
      case ThreadEntryType.text:
        return 'Text';
      case ThreadEntryType.media:
        return 'Media';
      case ThreadEntryType.location:
        return 'Location';
      case ThreadEntryType.checkin:
        return 'Check-in';
    }
  }

  String _getInputHint() {
    switch (_selectedType) {
      case ThreadEntryType.text:
        return 'Share your thoughts...';
      case ThreadEntryType.media:
        return 'Add a caption...';
      case ThreadEntryType.location:
        return _selectedPlace != null
            ? 'Add notes about ${_selectedPlace!.name}...'
            : 'Select a location above...';
      case ThreadEntryType.checkin:
        return _selectedPlace != null
            ? 'How was ${_selectedPlace!.name}?'
            : 'Select a place to check in...';
    }
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
