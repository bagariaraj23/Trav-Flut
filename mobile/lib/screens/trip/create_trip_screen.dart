import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/place_provider.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/widgets/loading_button.dart';
import 'dart:io';
import 'package:tripthread/services/media_service.dart';
import 'package:tripthread/widgets/place_autocomplete_field.dart';
import 'package:tripthread/utils/cloudinary_utils.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({super.key});

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _destinationController = TextEditingController();
  MediaService? _mediaService;
  Media? _selectedCoverMedia;
  bool _isUploadingCover = false;
  double? _coverUploadProgress;
  final List<Place> _destinations = [];
  DateTime? _startDate;
  DateTime? _endDate;
  TripMood? _selectedMood;
  TripType? _selectedType;

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _mediaService ??= context.read<MediaService>();
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? today : (today.add(const Duration(days: 1))),
      firstDate: isStartDate ? today : today,
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          debugPrint('[DEBUG] Start date selected: $picked');
          debugPrint('[DEBUG] Start date ISO: ${picked.toIso8601String()}');
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = null;
            debugPrint('[DEBUG] End date reset because it was before start date');
          }
        } else {
          _endDate = picked;
          debugPrint('[DEBUG] End date selected: $picked');
          debugPrint('[DEBUG] End date ISO: ${picked.toIso8601String()}');
        }
      });
    }
  }

  Future<void> _pickCoverImage({bool fromCamera = false}) async {
    try {
      final mediaService = _mediaService ?? context.read<MediaService>();
      final file = await mediaService.pickImage(fromCamera: fromCamera);
      if (file != null) {
        final fileSize = await file.length();
        setState(() {
          _selectedCoverMedia = Media(
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
            tripId: null,
            createdAt: DateTime.now(),
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error picking image: $e')),
      );
    }
  }

  Future<void> _createTrip() async {
    if (!_formKey.currentState!.validate()) return;

    if (_destinations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least one destination')),
      );
      return;
    }

    if (_startDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Start date is required')));
      return;
    }

    if (_endDate == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('End date is required')));
      return;
    }

    debugPrint('[DEBUG] Creating trip with dates:');
    debugPrint('[DEBUG] _startDate: $_startDate');
    debugPrint('[DEBUG] _endDate: $_endDate');

    if (_startDate != null) {
      debugPrint(
        '[DEBUG] startDate.toIso8601String(): ${_startDate!.toIso8601String()}',
      );
      debugPrint(
        '[DEBUG] startDate.millisecondsSinceEpoch: ${_startDate!.millisecondsSinceEpoch}',
      );
      debugPrint('[DEBUG] startDate timezone offset: ${_startDate!.timeZoneOffset}');
    }

    if (_endDate != null) {
      debugPrint(
        '[DEBUG] endDate.toIso8601String(): ${_endDate!.toIso8601String()}',
      );
      debugPrint(
        '[DEBUG] endDate.millisecondsSinceEpoch: ${_endDate!.millisecondsSinceEpoch}',
      );
      debugPrint('[DEBUG] endDate timezone offset: ${_endDate!.timeZoneOffset}');
    }

    if (_startDate != null) {
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (_startDate!.isBefore(today)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Start date cannot be in the past')),
        );
        return;
      }
    }

    if (_startDate != null && _endDate != null) {
      if (_endDate!.isBefore(_startDate!)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('End date must be after start date')),
        );
        return;
      }
    }

    String? coverMediaId;
    final mediaService = _mediaService ?? context.read<MediaService>();

    if (_selectedCoverMedia != null &&
        !_selectedCoverMedia!.url.startsWith('http')) {
      setState(() {
        _isUploadingCover = true;
        _coverUploadProgress = 0.0;
      });
      try {
        final uploadedMedia = await mediaService.uploadMediaToCloudinary(
          file: File(_selectedCoverMedia!.url),
          usage: 'trip_cover',
          onProgress: (progress) {
            if (!mounted) return;
            setState(() {
              _coverUploadProgress = progress;
            });
          },
        );

        if (uploadedMedia != null) {
          coverMediaId = uploadedMedia.id;
          setState(() {
            _selectedCoverMedia = uploadedMedia;
            _coverUploadProgress = 1.0;
          });
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to upload cover image: $e')),
          );
          setState(() {
            _isUploadingCover = false;
            _coverUploadProgress = null;
          });
        }
        return;
      } finally {
        if (mounted) {
          setState(() {
            _isUploadingCover = false;
            _coverUploadProgress = null;
          });
        }
      }
    } else if (_selectedCoverMedia != null) {
      coverMediaId = _selectedCoverMedia!.id.isEmpty
          ? null
          : _selectedCoverMedia!.id;
    }

    final request = CreateTripRequest(
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      startDate: _startDate,
      endDate: _endDate,
      destinations: _destinations.map((e) => e.name).toList(),
      destinationPlaceIds: _destinations.map((e) => e.id).toList(),
      mood: _selectedMood,
      type: _selectedType,
      coverMediaId: coverMediaId,
    );

    debugPrint('[DEBUG] CreateTripRequest created:');
    debugPrint('[DEBUG] request.toJson(): ${request.toJson()}');

    // Check if user wants to replace existing trip
    final routerState = GoRouterState.of(context);
    final extra = routerState.extra;
    final replaceExisting = extra is Map && extra['replaceExisting'] == true;
    final navigator = context;
    final messenger = ScaffoldMessenger.of(context);

    final tripProvider = context.read<TripProvider>();
    final success = await tripProvider.createTrip(
      request,
      replaceExisting: replaceExisting,
    );

    if (!mounted) return;
    if (success) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Trip started successfully! 🎉')),
      );
      navigator.go('/home');
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        context.go('/home', extra: {'explicitHome': true});
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Create Trip'),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () =>
                context.go('/home', extra: {'explicitHome': true}),
          ),
        ),
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header Banner
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      children: [
                        const Icon(
                          Icons.flight_takeoff,
                          size: 48,
                          color: Colors.white,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Ready for Adventure?',
                          style: Theme.of(context).textTheme.headlineMedium
                              ?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Start documenting your journey and create amazing memories',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(
                                color: Colors.white.withValues(alpha: 0.9),
                              ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Trip Title
                  CustomTextField(
                    controller: _titleController,
                    label: 'Trip Title',
                    hintText: 'e.g., Tokyo Adventure',
                    prefixIcon: Icons.title,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Trip title is required';
                      }
                      return null;
                    },
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),

                  // Description
                  CustomTextField(
                    controller: _descriptionController,
                    label: 'Description (Optional)',
                    hintText: 'Tell us about your trip...',
                    prefixIcon: Icons.description,
                    maxLines: 3,
                    maxLength: 500,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),

                  // Cover Image Picker
                  Text(
                    'Cover Image (Optional)',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_selectedCoverMedia != null)
                    Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _selectedCoverMedia!.url.startsWith('http')
                              ? Image.network(
                                  buildOptimizedImageUrl(
                                    _selectedCoverMedia!.url,
                                    width: 1600,
                                  ),
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                )
                              : Image.file(
                                  File(_selectedCoverMedia!.url),
                                  height: 160,
                                  width: double.infinity,
                                  fit: BoxFit.cover,
                                ),
                        ),
                        if (_isUploadingCover)
                          Positioned.fill(
                            child: Container(
                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 36,
                                      width: 36,
                                      child: CircularProgressIndicator(
                                        value: _coverUploadProgress?.clamp(
                                                0.0,
                                                1.0,
                                              ),
                                        strokeWidth: 3,
                                        backgroundColor: Colors.white24,
                                        valueColor:
                                            const AlwaysStoppedAnimation<Color>(
                                              Colors.white,
                                            ),
                                      ),
                                    ),
                                    if (_coverUploadProgress != null)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          top: 8.0,
                                        ),
                                        child: Text(
                                          '${(_coverUploadProgress!.clamp(0.0, 1.0) * 100).round()}%',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        Positioned(
                          top: 8,
                          right: 8,
                          child: CircleAvatar(
                            backgroundColor: Colors.black54,
                            child: IconButton(
                              icon: const Icon(
                                Icons.close,
                                color: Colors.white,
                              ),
                              onPressed: _isUploadingCover
                                  ? null
                                  : () {
                                      setState(() {
                                        _selectedCoverMedia = null;
                                      });
                                    },
                            ),
                          ),
                        ),
                      ],
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth > 400) {
                          return Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isUploadingCover
                                      ? null
                                      : () =>
                                            _pickCoverImage(fromCamera: false),
                                  icon: const Icon(Icons.photo_library),
                                  label: const Text('Gallery'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _isUploadingCover
                                      ? null
                                      : () => _pickCoverImage(fromCamera: true),
                                  icon: const Icon(Icons.camera_alt),
                                  label: const Text('Camera'),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isUploadingCover
                                    ? null
                                    : () => _pickCoverImage(fromCamera: false),
                                icon: const Icon(Icons.photo_library),
                                label: const Text('Gallery'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: _isUploadingCover
                                    ? null
                                    : () => _pickCoverImage(fromCamera: true),
                                icon: const Icon(Icons.camera_alt),
                                label: const Text('Camera'),
                                style: OutlinedButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 16),

                  // Destinations
                  Text(
                    'Destinations',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  PlaceAutocompleteField(
                    controller: _destinationController,
                    hintText: 'Search destinations...',
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.location_on),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    onPlaceSelected: (place) {
                      setState(() {
                        if (!_destinations.any((p) => p.id == place.id)) {
                          _destinations.add(place);
                        }
                        _destinationController.clear();
                      });
                      context.read<PlaceProvider>().clearSearchResults();
                      FocusScope.of(context).unfocus();
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_destinations.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _destinations.map((place) {
                        return Chip(
                          label: Text(place.name),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () {
                            setState(() {
                              _destinations.removeWhere(
                                (p) => p.id == place.id,
                              );
                            });
                          },
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.primaryContainer,
                        );
                      }).toList(),
                    ),
                  const SizedBox(height: 16),

                  // Dates
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Start Date',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _selectDate(context, true),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(
                                      alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _startDate != null
                                            ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                                            : 'Select date',
                                        style: TextStyle(
                                          color: _startDate != null
                                              ? null
                                              : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'End Date',
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w600),
                            ),
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _selectDate(context, false),
                              child: Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: Theme.of(context).colorScheme.onSurface.withValues(
                                      alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.10,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.calendar_today,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        _endDate != null
                                            ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                                            : 'Select date',
                                        style: TextStyle(
                                          color: _endDate != null
                                              ? null
                                              : Theme.of(context).colorScheme.onSurfaceVariant,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Trip Type
                  Text(
                    'Trip Type',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: TripType.values.map((type) {
                      final isSelected = _selectedType == type;
                      return FilterChip(
                        label: Text(_getTripTypeLabel(type)),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedType = selected ? type : null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 16),

                  // Trip Mood
                  Text(
                    'Trip Mood',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: TripMood.values.map((mood) {
                      final isSelected = _selectedMood == mood;
                      return FilterChip(
                        label: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_getTripMoodEmoji(mood)),
                            const SizedBox(width: 4),
                            Text(_getTripMoodLabel(mood)),
                          ],
                        ),
                        selected: isSelected,
                        onSelected: (selected) {
                          setState(() {
                            _selectedMood = selected ? mood : null;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 32),

                  // Error Message
                  Consumer<TripProvider>(
                    builder: (context, tripProvider, child) {
                      if (tripProvider.error != null) {
                        return Container(
                          margin: const EdgeInsets.only(bottom: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.error.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(
                                context,
                              ).colorScheme.error.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Text(
                            tripProvider.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 14,
                            ),
                          ),
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // Create Trip Button
                  Consumer<TripProvider>(
                    builder: (context, tripProvider, child) {
                      return LoadingButton(
                        onPressed: _createTrip,
                        isLoading: tripProvider.isLoading,
                        child: const Text('Start Trip'),
                      );
                    },
                  ),

                  // Bottom padding for keyboard
                  SizedBox(
                    height: MediaQuery.of(context).viewInsets.bottom > 0
                        ? 16
                        : 80,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
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
