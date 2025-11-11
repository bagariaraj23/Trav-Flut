import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/widgets/map_picker_sheet.dart';
import 'package:tripthread/widgets/place_search_sheet.dart';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

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
  final _placeSearchScrollController = ScrollController();

  Trip? _trip;
  bool _isLoading = true;
  ThreadEntryType _selectedType = ThreadEntryType.text;
  MediaService? _mediaService;
  Media? _selectedMediaForEntry;
  bool _isUploadingMedia = false;
  List<Media> _pendingMediaBatch = [];
  double? _uploadProgress;
  Place? _selectedPlace;
  VideoPlayerController? _pendingVideoController;
  bool _pendingVideoInitialized = false;

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

  @override
  void dispose() {
    _textController.dispose();
    _locationController.dispose();
    _scrollController.dispose();
    _disposePendingVideoController();
    super.dispose();
  }
  void _disposePendingVideoController() {
    _pendingVideoController?.dispose();
    _pendingVideoController = null;
    _pendingVideoInitialized = false;
  }

  Future<void> _setSelectedMedia(Media media) async {
    if (!mounted) return;

    if (media.type == MediaType.video) {
      _disposePendingVideoController();

      final controller = media.url.startsWith('http')
          ? VideoPlayerController.networkUrl(
              Uri.parse(buildOptimizedVideoUrl(media.url, maxWidth: 1280)),
            )
          : VideoPlayerController.file(File(media.url));

      setState(() {
        _selectedMediaForEntry = media;
        _selectedType = ThreadEntryType.media;
        _pendingVideoController = controller;
        _pendingVideoInitialized = false;
        _uploadProgress = null;
      });

      try {
        await controller.initialize();
        controller
          ..setLooping(true)
          ..setVolume(0)
          ..play();
        if (mounted) {
          setState(() {
            _pendingVideoInitialized = true;
          });
        }
      } catch (e) {
        debugPrint('[TripThread] Failed to initialize video preview: $e');
        if (mounted) {
          setState(() {
            _pendingVideoInitialized = false;
          });
        }
      }
    } else {
      _disposePendingVideoController();
      setState(() {
        _selectedMediaForEntry = media;
        _selectedType = ThreadEntryType.media;
        _uploadProgress = null;
      });
    }
  }

  void _clearSelectedMedia() {
    _disposePendingVideoController();
    setState(() {
      _selectedMediaForEntry = null;
      _uploadProgress = null;
      _pendingMediaBatch.clear();
    });
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
        success = await _handleMediaSubmission(tripProvider);
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
      final mediaService = _mediaService ?? context.read<MediaService>();
      final file = await mediaService.pickImage(fromCamera: fromCamera);
      if (file != null) {
        final fileSize = await file.length();
        final media = Media(
          id: '',
          url: file.path,
          publicId: '',
          type: mediaService.getMediaType(file),
          filename: mediaService.getFileName(file),
          size: fileSize,
          width: null,
          height: null,
          duration: null,
          processingStatus: MediaProcessingStatus.pending,
          uploadedById: '',
          tripId: widget.tripId,
          createdAt: DateTime.now(),
        );
        await _setSelectedMedia(media);
        if (!mounted) return;
        setState(() {
          _pendingMediaBatch.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _pickFromGallery() async {
    try {
      final mediaService = _mediaService ?? context.read<MediaService>();
      final files = await mediaService.pickMultipleMedia();
      if (files.isEmpty) {
        return;
      }

      final newMediaItems = <Media>[];

      for (final file in files) {
        final fileSize = await file.length();
        newMediaItems.add(
          Media(
            id: '',
            url: file.path,
            publicId: '',
            type: mediaService.getMediaType(file),
            filename: mediaService.getFileName(file),
            size: fileSize,
            width: null,
            height: null,
            duration: null,
            processingStatus: MediaProcessingStatus.pending,
            uploadedById: '',
            tripId: widget.tripId,
            createdAt: DateTime.now(),
          ),
        );
      }

      const maxQueued = 10;
      final totalCount =
          (_selectedMediaForEntry == null ? 0 : 1) + _pendingMediaBatch.length + newMediaItems.length;
      if (totalCount > maxQueued) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('You can queue at most $maxQueued media items at once.'),
          ),
        );
        return;
      }

      if (newMediaItems.isEmpty) {
        return;
      }

      if (_selectedMediaForEntry == null) {
        final first = newMediaItems.first;
        final remaining = newMediaItems.length > 1
            ? newMediaItems.sublist(1)
            : <Media>[];

        await _setSelectedMedia(first);
        if (!mounted) return;
        setState(() {
          _pendingMediaBatch = remaining;
        });
      } else {
        setState(() {
          _pendingMediaBatch = [
            ..._pendingMediaBatch,
            ...newMediaItems,
          ];
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking media: $e')),
      );
    }
  }

  Future<void> _pickVideo() async {
    try {
      final mediaService = _mediaService ?? context.read<MediaService>();
      final file = await mediaService.pickVideo();
      if (file != null) {
        final fileSize = await file.length();
        final media = Media(
          id: '',
          url: file.path,
          publicId: '',
          type: mediaService.getMediaType(file),
          filename: mediaService.getFileName(file),
          size: fileSize,
          width: null,
          height: null,
          duration: null,
          processingStatus: MediaProcessingStatus.pending,
          uploadedById: '',
          tripId: widget.tripId,
          createdAt: DateTime.now(),
        );
        await _setSelectedMedia(media);
        if (!mounted) return;
        setState(() {
          _pendingMediaBatch.clear();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking video: $e')),
      );
    }
  }

  Future<bool> _handleMediaSubmission(TripProvider tripProvider) async {
    if (_selectedMediaForEntry == null && _pendingMediaBatch.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select at least one media file')),
      );
      return false;
    }

    final caption = _textController.text.trim().isNotEmpty
        ? _textController.text.trim()
        : null;

    final allMedia = <Media>[
      if (_selectedMediaForEntry != null) _selectedMediaForEntry!,
      ..._pendingMediaBatch,
    ];

    if (allMedia.isEmpty) {
      return false;
    }

    bool allSucceeded = true;

    for (var index = 0; index < allMedia.length; index++) {
      final media = allMedia[index];

      if (index == 0) {
        setState(() {
          _isUploadingMedia = true;
          _uploadProgress = 0.0;
          _pendingMediaBatch = allMedia.length > 1
              ? allMedia.sublist(1)
              : <Media>[];
        });
      } else {
        await _setSelectedMedia(media);
        if (!mounted) return false;
        setState(() {
          _isUploadingMedia = true;
          _uploadProgress = 0.0;
          _pendingMediaBatch = allMedia.sublist(index + 1);
        });
      }

      try {
        final uploadedMedia =
            await _uploadSingleMediaForEntry(media, caption, tripProvider);
        allMedia[index] = uploadedMedia;
        if (mounted) {
          setState(() {
            _pendingMediaBatch = allMedia.sublist(index + 1);
          });
        }
      } catch (e) {
        allSucceeded = false;
        if (mounted) {
          debugPrint(
              '[TripThread] Failed to upload media item ${index + 1}/${allMedia.length}: $e');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to upload media ${index + 1}/${allMedia.length}: $e',
              ),
            ),
          );
          setState(() {
            _isUploadingMedia = false;
            _uploadProgress = null;
            _pendingMediaBatch = allMedia.sublist(index + 1);
          });
        }
        break;
      }
    }

    if (!mounted) {
      return allSucceeded;
    }

    if (allSucceeded) {
      _textController.clear();
      _clearSelectedMedia();
      setState(() {
        _isUploadingMedia = false;
        _uploadProgress = null;
        _pendingMediaBatch = [];
      });
    }

    return allSucceeded;
  }

  Future<Media> _uploadSingleMediaForEntry(
    Media media,
    String? caption,
    TripProvider tripProvider,
  ) async {
    final mediaService = _mediaService ?? context.read<MediaService>();
    Media resolvedMedia = media;

    if (!media.url.startsWith('http')) {
      final uploadedMedia = await mediaService.uploadMediaToCloudinary(
        file: File(media.url),
        tripId: widget.tripId,
        usage: 'thread_entry',
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _uploadProgress = progress;
          });
        },
      );

      if (uploadedMedia == null) {
        throw Exception('Media upload failed');
      }

      resolvedMedia = uploadedMedia;
    } else {
      if (mounted) {
        setState(() {
          _uploadProgress = 1.0;
        });
      }
    }

    if (resolvedMedia.id.isEmpty) {
      throw Exception('Missing media identifier after upload');
    }

    final success = await tripProvider.addMediaEntry(
      resolvedMedia.id,
      caption: caption,
      tripId: widget.tripId,
    );

    if (!success) {
      throw Exception('Failed to save media entry');
    }

    if (mounted) {
      setState(() {
        _uploadProgress = 1.0;
        _selectedMediaForEntry = resolvedMedia;
      });
    }

    return resolvedMedia;
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
                  if (entry.type == ThreadEntryType.media)
                    _buildMediaPreview(entry),

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

  Widget _buildMediaPreview(TripThreadEntry entry) {
    final mediaUrl = entry.media?.url ?? entry.mediaUrl;
    if (mediaUrl == null || mediaUrl.isEmpty) {
      return Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            const Icon(Icons.image_not_supported_outlined, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Media not available',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Colors.grey[600],
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final isVideo = entry.media?.type == MediaType.video;
    final heroTag = 'trip-media-${entry.id}';
    final previewUrl = isVideo
        ? buildVideoThumbnailUrl(mediaUrl, maxWidth: 1280)
        : buildOptimizedImageUrl(mediaUrl, width: 1600);

    return GestureDetector(
      onTap: () => _openMediaViewer(
        heroTag,
        isVideo
            ? buildOptimizedVideoUrl(mediaUrl, maxWidth: 1920)
            : buildOptimizedImageUrl(mediaUrl, width: 2048),
        isVideo,
      ),
      child: Container(
        margin: const EdgeInsets.only(top: 8),
        constraints: const BoxConstraints(
          maxHeight: 300,
          minHeight: 180,
        ),
        decoration: BoxDecoration(
          color: Colors.black12,
          borderRadius: BorderRadius.circular(12),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Hero(
              tag: heroTag,
              child: Image.network(
                previewUrl,
                fit: BoxFit.cover,
                width: double.infinity,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    color: Colors.grey[200],
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.broken_image,
                            size: 48, color: Colors.grey),
                        const SizedBox(height: 8),
                        Text(
                          'Failed to load media',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (isVideo)
              Align(
                alignment: Alignment.center,
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.45),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 48,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _openMediaViewer(String heroTag, String mediaUrl, bool isVideo) {
    if (isVideo) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => _TripVideoViewer(
            heroTag: heroTag,
            mediaUrl: mediaUrl,
          ),
          fullscreenDialog: true,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: Container(
            color: Colors.black.withOpacity(0.95),
            child: SafeArea(
              child: Stack(
                children: [
                  Center(
                    child: Hero(
                      tag: heroTag,
                      child: InteractiveViewer(
                        maxScale: 5.0,
                        minScale: 0.5,
                        child: Image.network(
                          buildOptimizedImageUrl(mediaUrl, width: 2400),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Padding(
                              padding: const EdgeInsets.all(24.0),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white70,
                                    size: 64,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'Unable to load media.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(color: Colors.white70),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                  if (isVideo)
                    Positioned(
                      bottom: 24,
                      left: 0,
                      right: 0,
                      child: Column(
                        children: [
                          const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 48,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Video playback coming soon',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: Colors.white70),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close, color: Colors.white),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.black45,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
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
                          if (_selectedMediaForEntry != null)
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.15),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.25),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      _buildPendingMediaThumbnail(),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _selectedMediaForEntry!.filename ??
                                                  'Selected media',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                                fontSize: 14,
                                                color: Colors.white,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 4),
                                            Text(
                                              _selectedMediaForEntry!.size != null
                                                  ? '${(_selectedMediaForEntry!.size! / 1024 / 1024).toStringAsFixed(1)} MB'
                                                  : 'Selected',
                                              style: TextStyle(
                                                color: Colors.white70,
                                                fontSize: 12,
                                              ),
                                            ),
                                            if (_selectedMediaForEntry!.type ==
                                                    MediaType.video &&
                                                _pendingVideoController != null)
                                              Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2.0),
                                                child: Text(
                                                  _pendingVideoInitialized
                                                      ? _formatDuration(
                                                          _pendingVideoController!
                                                              .value.duration)
                                                      : 'Loading preview...',
                                                  style: TextStyle(
                                                    color: Colors.white60,
                                                    fontSize: 12,
                                                  ),
                                                ),
                                              ),
                                          ],
                                        ),
                                      ),
                                      IconButton(
                                        onPressed: _isUploadingMedia
                                            ? null
                                            : _clearSelectedMedia,
                                        icon: const Icon(Icons.close, size: 20),
                                        style: IconButton.styleFrom(
                                          backgroundColor: Colors.white12,
                                          foregroundColor: Colors.white,
                                          visualDensity: VisualDensity.compact,
                                          padding: const EdgeInsets.all(8),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_pendingMediaBatch.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8.0),
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 4,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.white12,
                                          borderRadius: BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '${_pendingMediaBatch.length} more ${_pendingMediaBatch.length == 1 ? 'item' : 'items'} queued',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                    ),
                                  if (_isUploadingMedia)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 12.0),
                                      child: LinearProgressIndicator(
                                        value: _uploadProgress != null
                                            ? _uploadProgress!.clamp(0.0, 1.0)
                                            : null,
                                        backgroundColor: Colors.white12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .secondary,
                                        minHeight: 6,
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
                                          onPressed: _isUploadingMedia
                                              ? null
                                              : _pickFromGallery,
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
                                          onPressed: _isUploadingMedia
                                              ? null
                                              : () =>
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
                                          onPressed: _isUploadingMedia
                                              ? null
                                              : _pickVideo,
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
                                            onPressed: _isUploadingMedia
                                                ? null
                                                : _pickFromGallery,
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
                                            onPressed: _isUploadingMedia
                                                ? null
                                                : () => _pickImage(
                                                      fromCamera: true),
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
                                        onPressed: _isUploadingMedia
                                            ? null
                                            : _pickVideo,
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

  Widget _buildPendingMediaThumbnail() {
    final media = _selectedMediaForEntry!;
    final borderRadius = BorderRadius.circular(10);

    Widget content;
    if (media.type == MediaType.image) {
      final imageWidget = media.url.startsWith('http')
          ? Image.network(
              buildOptimizedImageUrl(media.url, width: 360, height: 360),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            )
          : Image.file(
              File(media.url),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.grey[300],
                child: const Icon(Icons.broken_image, color: Colors.grey),
              ),
            );
      content = imageWidget;
    } else {
      if (_pendingVideoController != null && _pendingVideoInitialized) {
        content = Stack(
          fit: StackFit.expand,
          children: [
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _pendingVideoController!.value.size.width,
                height: _pendingVideoController!.value.size.height,
                child: VideoPlayer(_pendingVideoController!),
              ),
            ),
            const Align(
              alignment: Alignment.center,
              child: Icon(Icons.play_circle_fill,
                  color: Colors.white, size: 36),
            ),
          ],
        );
      } else {
        content = media.url.startsWith('http')
            ? Image.network(
                buildVideoThumbnailUrl(media.url, maxWidth: 360),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black54,
                  child: const Center(
                    child: Icon(Icons.videocam, color: Colors.white, size: 32),
                  ),
                ),
              )
            : Container(
                color: Colors.black54,
                child: const Center(
                  child: Icon(Icons.videocam, color: Colors.white, size: 32),
                ),
              );
      }
    }

    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: 72,
        height: 72,
        child: content,
      ),
    );
  }

  String _formatDuration(Duration duration) {
    if (duration.inHours >= 1) {
      final hours = duration.inHours;
      final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
      final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$hours:$minutes:$seconds';
    } else {
      final minutes = duration.inMinutes.toString().padLeft(2, '0');
      final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
      return '$minutes:$seconds';
    }
  }
}

class _TripVideoViewer extends StatefulWidget {
  final String heroTag;
  final String mediaUrl;

  const _TripVideoViewer({
    required this.heroTag,
    required this.mediaUrl,
  });

  @override
  State<_TripVideoViewer> createState() => _TripVideoViewerState();
}

class _TripVideoViewerState extends State<_TripVideoViewer> {
  late final VideoPlayerController _controller;
  bool _isInitialized = false;
  bool _isPlaying = true;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(
      Uri.parse(buildOptimizedVideoUrl(widget.mediaUrl, maxWidth: 1920)),
    )
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {
          _isInitialized = true;
        });
        _controller
          ..setLooping(true)
          ..play();
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _isPlaying = false;
      } else {
        _controller.play();
        _isPlaying = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          children: [
            Center(
              child: Hero(
                tag: widget.heroTag,
                child: _isInitialized
                    ? GestureDetector(
                        onTap: _togglePlayback,
                        child: AspectRatio(
                          aspectRatio: _controller.value.aspectRatio,
                          child: VideoPlayer(_controller),
                        ),
                      )
                    : const CircularProgressIndicator(),
              ),
            ),
            Positioned(
              top: 16,
              right: 16,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close, color: Colors.white),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black45,
                ),
              ),
            ),
            if (_isInitialized)
              Positioned(
                bottom: 24,
                left: 0,
                right: 0,
                child: Center(
                  child: IconButton(
                    onPressed: _togglePlayback,
                    icon: Icon(
                      _isPlaying ? Icons.pause_circle : Icons.play_circle,
                      color: Colors.white,
                      size: 48,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
