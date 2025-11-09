import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:tripthread/providers/trip_provider.dart';
import 'package:tripthread/providers/auth_provider.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/widgets/custom_text_field.dart';
import 'package:tripthread/widgets/loading_button.dart';
import 'dart:io';
import 'package:tripthread/services/media_service.dart';

class CreateTripScreen extends StatefulWidget {
  const CreateTripScreen({Key? key}) : super(key: key);

  @override
  State<CreateTripScreen> createState() => _CreateTripScreenState();
}

class _CreateTripScreenState extends State<CreateTripScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _destinationController = TextEditingController();

  MediaService? _mediaService;
  File? _selectedCoverFile;
  Media? _selectedCoverMedia;

  final List<String> _destinations = [];
  DateTime? _startDate;
  DateTime? _endDate;
  TripMood? _selectedMood;
  TripType? _selectedType;
  bool _isUploadingMedia = false;

  @override
  void initState() {
    super.initState();
    // Get MediaService from provider
    _mediaService = Provider.of<MediaService>(context, listen: false);
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _destinationController.dispose();
    super.dispose();
  }

  void _addDestination() {
    final destination = _destinationController.text.trim();
    if (destination.isNotEmpty && !_destinations.contains(destination)) {
      setState(() {
        _destinations.add(destination);
        _destinationController.clear();
      });
    }
  }

  void _removeDestination(String destination) {
    setState(() {
      _destinations.remove(destination);
    });
  }

  Future<void> _selectDate(BuildContext context, bool isStartDate) async {
    final DateTime now = DateTime.now();
    final DateTime today =
        DateTime(now.year, now.month, now.day); // Start of today

    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isStartDate ? today : (today.add(const Duration(days: 1))),
      firstDate: isStartDate ? today : today, // Start date can't be in the past
      lastDate: now.add(const Duration(days: 365)),
    );

    if (picked != null) {
      setState(() {
        if (isStartDate) {
          _startDate = picked;
          print('[DEBUG] Start date selected: $picked');
          print('[DEBUG] Start date ISO: ${picked.toIso8601String()}');

          // Reset end date if it's before start date
          if (_endDate != null && _endDate!.isBefore(picked)) {
            _endDate = null;
            print('[DEBUG] End date reset because it was before start date');
          }
        } else {
          _endDate = picked;
          print('[DEBUG] End date selected: $picked');
          print('[DEBUG] End date ISO: ${picked.toIso8601String()}');
        }
      });
    }
  }

  Future<void> _pickCoverImage({bool fromCamera = false}) async {
    try {
      final file = await _mediaService?.pickImage(fromCamera: fromCamera);
      if (file != null) {
        setState(() {
          _selectedCoverFile = file;
          // Create a temporary Media object for preview
          _selectedCoverMedia = Media(
            id: '', // Temporary ID
            url: file.path, // Local file path for preview
            publicId: '', // Temporary
            type: _mediaService!.getMediaType(file),
            uploadedById: '', // Temporary
            createdAt: DateTime.now(),
          );
        });
      }
    } catch (e) {
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

    // Add debugging logs
    print('[DEBUG] Creating trip with dates:');
    print('[DEBUG] _startDate: $_startDate');
    print('[DEBUG] _endDate: $_endDate');

    if (_startDate != null) {
      print(
          '[DEBUG] startDate.toIso8601String(): ${_startDate!.toIso8601String()}');
      print(
          '[DEBUG] startDate.millisecondsSinceEpoch: ${_startDate!.millisecondsSinceEpoch}');
      print('[DEBUG] startDate timezone offset: ${_startDate!.timeZoneOffset}');
    }

    if (_endDate != null) {
      print(
          '[DEBUG] endDate.toIso8601String(): ${_endDate!.toIso8601String()}');
      print(
          '[DEBUG] endDate.millisecondsSinceEpoch: ${_endDate!.millisecondsSinceEpoch}');
      print('[DEBUG] endDate timezone offset: ${_endDate!.timeZoneOffset}');
    }

    // Validate dates before creating request
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

    final tripProvider = context.read<TripProvider>();
    final authProvider = context.read<AuthProvider>();
    final currentUserId = authProvider.currentUser?.id;

    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('User not authenticated.')),
      );
      return;
    }

    String? coverMediaId;
    
    // Upload cover media if selected
    if (_selectedCoverFile != null && _mediaService != null) {
      setState(() {
        _isUploadingMedia = true;
      });
      
      try {
        // First create a temporary trip to get tripId for media upload
        final tempRequest = CreateTripRequest(
          title: _titleController.text.trim(),
          description: _descriptionController.text.trim().isEmpty
              ? null
              : _descriptionController.text.trim(),
          startDate: _startDate,
          endDate: _endDate,
          destinations: _destinations,
          mood: _selectedMood,
          type: _selectedType,
        );

        // Create trip first
        final success = await tripProvider.createTrip(tempRequest);
        
        if (success && tripProvider.currentTrip != null) {
          // Now upload media for the created trip
          final uploadedMedia = await _mediaService!.uploadMediaToCloudinary(
            _selectedCoverFile!,
            tripProvider.currentTrip!.id,
          );
          
          if (uploadedMedia != null) {
            coverMediaId = uploadedMedia.id;
            
            // For now, we'll just show success
            // TODO: Update trip with cover media ID when update endpoint is available
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Trip created successfully with cover image! 🎉')),
            );
            context.go('/home');
            return;
          }
        }
        
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Trip started successfully! 🎉')),
          );
          context.go('/home');
        }
      } catch (e) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload cover image: ${e.toString()}')),
        );
      } finally {
        setState(() {
          _isUploadingMedia = false;
        });
      }
    } else {
      // Create trip without cover media
      final request = CreateTripRequest(
        title: _titleController.text.trim(),
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        startDate: _startDate,
        endDate: _endDate,
        destinations: _destinations,
        mood: _selectedMood,
        type: _selectedType,
        coverMediaId: coverMediaId,
      );

      print('[DEBUG] CreateTripRequest created:');
      print('[DEBUG] request.toJson(): ${request.toJson()}');

      final success = await tripProvider.createTrip(request);

      if (success && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Trip started successfully! 🎉')),
        );
        context.go('/home');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final extra = GoRouterState.of(context).extra;
    final from = (extra is Map && extra['from'] != null)
        ? extra['from'] as String
        : '/home';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Start New Trip'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Theme.of(context).colorScheme.primary,
                      Theme.of(context).colorScheme.primary.withOpacity(0.8),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  children: [
                    Icon(
                      Icons.flight_takeoff,
                      size: 48,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Ready for Adventure?',
                      style:
                          Theme.of(context).textTheme.headlineMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start documenting your journey and create amazing memories',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: Colors.white.withOpacity(0.9),
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
                hintText: 'e.g., Tokyo Adventure 2024',
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
              if (_selectedCoverFile != null)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.file(
                        _selectedCoverFile!,
                        height: 160,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: CircleAvatar(
                        backgroundColor: Colors.black54,
                        child: IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () {
                            setState(() {
                              _selectedCoverFile = null;
                              _selectedCoverMedia = null;
                            });
                          },
                        ),
                      ),
                    ),
                    if (_isUploadingMedia)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(color: Colors.white),
                                SizedBox(height: 8),
                                Text(
                                  'Uploading image...',
                                  style: TextStyle(color: Colors.white),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                )
              else
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickCoverImage(fromCamera: false),
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
                        onPressed: () => _pickCoverImage(fromCamera: true),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Camera'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ],
                ),

              const SizedBox(height: 16),

              // Destinations
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Destinations',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _destinationController,
                          decoration: InputDecoration(
                            hintText: 'Add destination',
                            prefixIcon: const Icon(Icons.location_on),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _addDestination,
                            ),
                          ),
                          onFieldSubmitted: (_) => _addDestination(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_destinations.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _destinations.map((destination) {
                        return Chip(
                          label: Text(destination),
                          deleteIcon: const Icon(Icons.close, size: 18),
                          onDeleted: () => _removeDestination(destination),
                          backgroundColor:
                              Theme.of(context).colorScheme.primaryContainer,
                        );
                      }).toList(),
                    ),
                ],
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectDate(context, true),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    color: Colors.grey[600]),
                                const SizedBox(width: 12),
                                Text(
                                  _startDate != null
                                      ? '${_startDate!.day}/${_startDate!.month}/${_startDate!.year}'
                                      : 'Select date',
                                  style: TextStyle(
                                    color: _startDate != null
                                        ? null
                                        : Colors.grey[600],
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
                          style:
                              Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: () => _selectDate(context, false),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey[300]!),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today,
                                    color: Colors.grey[600]),
                                const SizedBox(width: 12),
                                Text(
                                  _endDate != null
                                      ? '${_endDate!.day}/${_endDate!.month}/${_endDate!.year}'
                                      : 'Select date',
                                  style: TextStyle(
                                    color: _endDate != null
                                        ? null
                                        : Colors.grey[600],
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                ],
              ),

              const SizedBox(height: 16),

              // Trip Mood
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                ],
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
                        color: Theme.of(context)
                            .colorScheme
                            .error
                            .withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: Theme.of(context)
                              .colorScheme
                              .error
                              .withOpacity(0.3),
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
            ],
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
