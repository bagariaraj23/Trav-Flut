import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/services/media_service.dart';
import 'dart:io';
import 'package:go_router/go_router.dart';

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

  Trip? _trip;
  bool _isLoading = true;
  ThreadEntryType _selectedType = ThreadEntryType.text;
  File? _selectedMediaFile;
  bool _isUploadingMedia = false;

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
        await tripProvider.loadCurrentTripEntries();
      }
    }
  }

  Future<void> _addEntry() async {
    final tripProvider = context.read<TripProvider>();
    bool success = false;

    switch (_selectedType) {
      case ThreadEntryType.text:
        if (_textController.text.trim().isNotEmpty) {
          success =
              await tripProvider.addTextEntry(_textController.text.trim());
          if (success) _textController.clear();
        }
        break;
      case ThreadEntryType.location:
        if (_locationController.text.trim().isNotEmpty) {
          success = await tripProvider.addLocationEntry(
            _locationController.text.trim(),
            notes: _textController.text.trim().isEmpty
                ? null
                : _textController.text.trim(),
          );
          if (success) {
            _locationController.clear();
            _textController.clear();
          }
        }
        break;
      case ThreadEntryType.media:
        if (_selectedMediaFile != null) {
          setState(() {
            _isUploadingMedia = true;
          });

          try {
            // For now, we'll use a placeholder URL since we don't have actual file upload
            // In a real app, you'd upload the file to a server and get back a URL
            final mediaUrl =
                "https://example.com/placeholder-media.jpg"; // Placeholder
            success = await tripProvider.addMediaEntry(
              mediaUrl,
              caption: _textController.text.trim().isEmpty
                  ? null
                  : _textController.text.trim(),
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
        if (_locationController.text.trim().isNotEmpty) {
          success = await tripProvider.addLocationEntry(
            _locationController.text.trim(),
            notes: _textController.text.trim().isEmpty
                ? null
                : _textController.text.trim(),
          );
          if (success) {
            _locationController.clear();
            _textController.clear();
          }
        }
        break;
    }

    if (success) {
      // Scroll to bottom to show new entry
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

  Future<void> _pickMedia() async {
    try {
      final file = await _mediaService.pickFile();
      if (file != null) {
        setState(() {
          _selectedMediaFile = file;
        });

        // Auto-switch to media type
        setState(() {
          _selectedType = ThreadEntryType.media;
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking media: $e')),
      );
    }
  }

  Future<void> _pickImage({bool fromCamera = false}) async {
    try {
      final file = await _mediaService.pickImage(fromCamera: fromCamera);
      if (file != null) {
        setState(() {
          _selectedMediaFile = file;
        });

        // Auto-switch to media type
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

        // Auto-switch to media type
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
    final canAddEntries =
        currentUser?.id == _trip!.userId && _trip!.status == TripStatus.ongoing;

    return Scaffold(
      appBar: AppBar(
        title: Text(_trip?.title ?? 'Trip Thread'),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            // Get the 'from' parameter or default to trip detail
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
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.timeline,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'No entries yet',
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(
                                color: Colors.grey[600],
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          canAddEntries
                              ? 'Start documenting your journey!'
                              : 'This trip has no entries yet',
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    color: Colors.grey[500],
                                  ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
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
          CircleAvatar(
            radius: 20,
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage: entry.author.avatarUrl != null
                ? NetworkImage(entry.author.avatarUrl!)
                : null,
            child: entry.author.avatarUrl == null
                ? Text(
                    entry.author.name?.substring(0, 1).toUpperCase() ?? 'U',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                : null,
          ),

          const SizedBox(width: 12),

          // Entry content
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isCurrentUser
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    children: [
                      Text(
                        entry.author.name ?? 'User',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                      const SizedBox(width: 8),
                      _buildEntryTypeIcon(entry.type),
                      const Spacer(),
                      Text(
                        _formatDateTime(entry.createdAt),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[600],
                            ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 8),

                  // Content
                  if (entry.contentText != null) ...[
                    Text(
                      entry.contentText!,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 8),
                  ],

                  // Location
                  if (entry.locationName != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .primary
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.location_on,
                            size: 16,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            entry.locationName!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),

                  // Media placeholder
                  if (entry.type == ThreadEntryType.media &&
                      entry.mediaUrl != null)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      height: 200,
                      decoration: BoxDecoration(
                        color: Colors.grey[200],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(Icons.image, size: 48, color: Colors.grey),
                      ),
                    ),

                  // Tagged users
                  if (entry.taggedUsers != null &&
                      entry.taggedUsers!.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      child: Wrap(
                        spacing: 4,
                        children: entry.taggedUsers!.map((user) {
                          return Chip(
                            label: Text(
                              '@${user.username ?? user.name ?? 'User'}',
                              style: const TextStyle(fontSize: 12),
                            ),
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                            visualDensity: VisualDensity.compact,
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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: Column(
        children: [
          // Entry type selector
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
                        Text(_getEntryTypeLabel(type)),
                      ],
                    ),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        _selectedType = type;
                      });
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          const SizedBox(height: 12),

          // Input fields based on type
          if (_selectedType == ThreadEntryType.location) ...[
            CustomTextField(
              controller: _locationController,
              label: 'Location',
              hintText: 'Where are you?',
              prefixIcon: Icons.location_on,
            ),
            const SizedBox(height: 8),
          ],

          // Media selection for media type
          if (_selectedType == ThreadEntryType.media) ...[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Media',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (_selectedMediaFile != null) ...[
                    // Show selected media
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _selectedMediaFile!.path
                                            .split('.')
                                            .last
                                            .toLowerCase() ==
                                        'mp4' ||
                                    _selectedMediaFile!.path
                                            .split('.')
                                            .last
                                            .toLowerCase() ==
                                        'mov' ||
                                    _selectedMediaFile!.path
                                            .split('.')
                                            .last
                                            .toLowerCase() ==
                                        'avi'
                                ? Icons.video_file
                                : Icons.image,
                            color: Colors.grey[600],
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _selectedMediaFile!.path.split('/').last,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w500),
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
                            ),
                          ),
                        ],
                      ),
                    ),
                  ] else ...[
                    // Media picker buttons
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(fromCamera: false),
                            icon: const Icon(Icons.photo_library),
                            label: const Text('Gallery'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () => _pickImage(fromCamera: true),
                            icon: const Icon(Icons.camera_alt),
                            label: const Text('Camera'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _pickVideo,
                            icon: const Icon(Icons.video_file),
                            label: const Text('Video'),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
          ],

          // Text input (always shown for notes/captions)
          Row(
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
                  ),
                  maxLines: null,
                  textCapitalization: TextCapitalization.sentences,
                ),
              ),
              const SizedBox(width: 8),
              Consumer<TripProvider>(
                builder: (context, tripProvider, child) {
                  return IconButton(
                    onPressed: (tripProvider.isLoading || _isUploadingMedia)
                        ? null
                        : _addEntry,
                    icon: (tripProvider.isLoading || _isUploadingMedia)
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    style: IconButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      foregroundColor: Colors.white,
                    ),
                  );
                },
              ),
            ],
          ),

          // Error message
          Consumer<TripProvider>(
            builder: (context, tripProvider, child) {
              if (tripProvider.error != null) {
                return Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.error.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tripProvider.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 12,
                    ),
                  ),
                );
              }
              return const SizedBox.shrink();
            },
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
        return 'Add notes about this place...';
      case ThreadEntryType.checkin:
        return 'How was your experience?';
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
