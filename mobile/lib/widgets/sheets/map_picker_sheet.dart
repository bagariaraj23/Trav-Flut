import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/place_provider.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:tripthread/utils/app_permissions.dart';
import 'package:tripthread/utils/app_theme.dart';
import 'package:tripthread/utils/map_place_label.dart';
import 'package:provider/provider.dart';

class MapPickerModal extends StatefulWidget {
  // final Function(Place place) onPlaceSelected;
  final String? initialPlaceName;
  final double? initialLat;
  final double? initialLng;

  const MapPickerModal({
    super.key,
    // required this.onPlaceSelected,
    this.initialPlaceName,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<MapPickerModal> createState() => _MapPickerModalState();
}

class _MapPickerModalState extends State<MapPickerModal> {
  mapbox.MapboxMap? _mapboxMap;
  Position? _currentPosition;
  bool _loading = true;
  bool _error = false;
  String _errorMessage = '';
  mapbox.Point? _selectedPoint;
  String? _selectedName;
  bool _isConfirmingLocation = false;
  bool _isDisposed = false;

  Timer? _debounceTimer;

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);

    if (widget.initialLat != null && widget.initialLng != null) {
      _selectedPoint = mapbox.Point(
        coordinates: mapbox.Position(widget.initialLng!, widget.initialLat!),
      );
      _selectedName = widget.initialPlaceName;
      setState(() => _loading = false);
    } else {
      _getCurrentLocation();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    _debounceTimer?.cancel();
    _mapboxMap = null;
    super.dispose();
  }

  // Only update state if not disposed
  void _safeSetState(VoidCallback fn) {
    if (!_isDisposed && mounted) {
      setState(fn);
    }
  }

  void _onCameraChanged(mapbox.CameraChangedEventData event) {
    if (_isDisposed) return;

    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 50), () {
      _safeSetState(() {
        _selectedPoint = event.cameraState.center;
            });
    });
  }

  Future<void> _getCurrentLocation() async {
    _safeSetState(() {
      _loading = true;
      _error = false;
      _errorMessage = '';
    });

    try {
      final access = await AppPermissions.ensure(AppPermissionKind.location);
      if (access != AppPermissionOutcome.granted) {
        throw AppPermissionException(
          AppPermissions.deniedMessage(AppPermissionKind.location),
        );
      }

      _currentPosition =
          await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 5),
            ),
          ).timeout(
            const Duration(seconds: 7),
            onTimeout: () => throw Exception('GPS fetch timed out'),
          );

      final point = mapbox.Point(
        coordinates: mapbox.Position(
          _currentPosition!.longitude,
          _currentPosition!.latitude,
        ),
      );

      _safeSetState(() {
        _selectedPoint = point;
        _loading = false;
      });

      if (_mapboxMap != null) {
        await _mapboxMap!.flyTo(
          mapbox.CameraOptions(center: point, zoom: 15.0),
          mapbox.MapAnimationOptions(duration: 800),
        );
      }
    } on AppPermissionException catch (e) {
      _safeSetState(() {
        _error = true;
        _errorMessage = e.message;
        _loading = false;
      });
    } catch (e) {
      debugPrint('[MapPickerModal] Error getting location: $e');
      _safeSetState(() {
        _error = true;
        _errorMessage = 'Could not get your location';
        _loading = false;
      });
    }
  }

  void _confirmLocation() async {
    if (_selectedPoint == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Please select a location')));
      return;
    }

    _safeSetState(() => _isConfirmingLocation = true);

    try {
      final placeProvider = context.read<PlaceProvider>();
      final lat = _selectedPoint!.coordinates.lat.toDouble();
      final lng = _selectedPoint!.coordinates.lng.toDouble();
      var name = _selectedName;
      String? address;
      if (isFallbackPinTitle(name)) {
        final label = await labelForPin(lat, lng);
        name = label.title;
        address = label.subtitle;
      }

      final placeCandidate = Place(
        id: '',
        name: name ?? fallbackPinTitle,
        address: address,
        lat: lat,
        lng: lng,
        placeType: PlaceType.poi,
        source: PlaceSource.user,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      debugPrint('[MapPickerModal] Resolving place: ${placeCandidate.name}');

      final resolvedPlace = await placeProvider
          .resolvePlace(placeCandidate)
          .timeout(const Duration(seconds: 30));

      if (resolvedPlace != null && mounted) {
        debugPrint('[MapPickerModal] Place resolved: ${resolvedPlace.id}');

        // Call callback first, then navigate
        // widget.onPlaceSelected(resolvedPlace);

        // // Proper navigation - use Future.microtask to avoid locked state
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            Navigator.of(context).pop(resolvedPlace);
          }
        });
      } else {
        _safeSetState(() => _isConfirmingLocation = false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to resolve location. Try again.'),
            ),
          );
        }
      }
    } on TimeoutException catch (e) {
      debugPrint('[MapPickerModal] Timeout: $e');
      _safeSetState(() => _isConfirmingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request timed out. Try again.')),
        );
      }
    } catch (e) {
      debugPrint('[MapPickerModal] Error: $e');
      _safeSetState(() => _isConfirmingLocation = false);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Stack(
          children: [
            // Map
            _loading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppTheme.accent),
                        const SizedBox(height: 16),
                        Text(
                          'Getting your location...',
                          style: TextStyle(color: scheme.onSurface),
                        ),
                      ],
                    ),
                  )
                : _error
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.location_off,
                          size: 64,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _errorMessage,
                          style: TextStyle(color: scheme.onSurface),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _getCurrentLocation,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  )
                : mapbox.MapWidget(
                    key: const ValueKey('mapbox-modal'),
                    styleUri: 'mapbox://styles/mapbox/streets-v12',
                    cameraOptions: mapbox.CameraOptions(
                      center:
                          _selectedPoint ??
                          mapbox.Point(coordinates: mapbox.Position(0, 20)),
                      zoom: 15.0,
                    ),
                    onMapCreated: (controller) {
                      if (!_isDisposed) {
                        _mapboxMap = controller;
                        debugPrint('[MapPickerModal] Map created');
                      }
                    },
                    onCameraChangeListener: _onCameraChanged,
                    onTapListener: (mapbox.MapContentGestureContext context) {
                      _safeSetState(() {
                        _selectedPoint = context.point;
                      });

                      // Animate to tapped location
                      _mapboxMap?.easeTo(
                        mapbox.CameraOptions(
                          center: context.point,
                          zoom: 15.0,
                        ),
                        mapbox.MapAnimationOptions(duration: 300),
                      );
                                        },
                  ),

            // Pin
            if (!_loading && !_error)
              Center(
                child: Transform.translate(
                  offset: const Offset(0, -22),
                  child: Icon(
                    Icons.location_on,
                    size: 48,
                    color: AppTheme.accent,
                    shadows: [
                      Shadow(
                        blurRadius: 8,
                        color: scheme.shadow.withValues(alpha: 0.35),
                      ),
                    ],
                  ),
                ),
              ),

            // Top bar
            Positioned(
              top: 12,
              left: 12,
              right: 72,
              child: Row(
                children: [
                  Material(
                    color: scheme.surface,
                    elevation: 2,
                    shape: const CircleBorder(),
                    child: IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close, color: scheme.onSurface),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Material(
                      color: scheme.surface,
                      elevation: 2,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        child: Text(
                          'Select location',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // GPS button
            if (!_loading && !_error)
              Positioned(
                top: 16,
                right: 16,
                child: FloatingActionButton(
                  heroTag: 'gps-modal',
                  mini: true,
                  onPressed: () async {
                    // Capture messenger before async operation to satisfy analyzer
                    final messenger = ScaffoldMessenger.of(context);
                    _safeSetState(() => _loading = true);
                    try {
                      final access = await AppPermissions.ensure(
                        AppPermissionKind.location,
                      );
                      if (access != AppPermissionOutcome.granted) {
                        throw AppPermissionException(
                          AppPermissions.deniedMessage(
                            AppPermissionKind.location,
                          ),
                        );
                      }
                      final position = await Geolocator.getCurrentPosition(
                        locationSettings: const LocationSettings(
                        accuracy: LocationAccuracy.medium,
                        timeLimit: Duration(seconds: 15),
                      ),
                      );

                      final point = mapbox.Point(
                        coordinates: mapbox.Position(
                          position.longitude,
                          position.latitude,
                        ),
                      );

                      _safeSetState(() {
                        _selectedPoint = point;
                        _loading = false;
                      });

                      if (_mapboxMap != null && !_isDisposed) {
                        await _mapboxMap!.flyTo(
                          mapbox.CameraOptions(center: point, zoom: 15.0),
                          mapbox.MapAnimationOptions(duration: 800),
                        );
                      }
                    } on TimeoutException {
                      _safeSetState(() => _loading = false);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('GPS timeout. Please try again.'),
                        ),
                      );
                    } on LocationServiceDisabledException {
                      _safeSetState(() => _loading = false);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Please enable location services'),
                        ),
                      );
                    } on AppPermissionException catch (e) {
                      _safeSetState(() => _loading = false);
                      messenger.showSnackBar(SnackBar(content: Text(e.message)));
                    } catch (e) {
                      _safeSetState(() => _loading = false);
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text('Could not get location'),
                        ),
                      );
                    }
                  },
                  backgroundColor: scheme.surface,
                  foregroundColor: AppTheme.accent,
                  child: const Icon(Icons.my_location),
                ),
              ),

            // Bottom controls
            if (!_loading && !_error)
              Positioned(
                bottom: 16,
                left: 16,
                right: 16,
                child: Material(
                  color: scheme.surface,
                  elevation: 6,
                  borderRadius: BorderRadius.circular(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_selectedPoint != null) ...[
                        Text(
                          'Selected location',
                          style: TextStyle(
                            color: scheme.onSurface,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_selectedPoint!.coordinates.lat.toStringAsFixed(5)}, ${_selectedPoint!.coordinates.lng.toStringAsFixed(5)}',
                          style: TextStyle(
                            color: scheme.onSurfaceVariant,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],

                      // Button
                      ElevatedButton.icon(
                        onPressed: _isConfirmingLocation
                            ? null
                            : _confirmLocation,
                        icon: _isConfirmingLocation
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.check, size: 24),
                        label: Text(
                          _isConfirmingLocation
                              ? 'Confirming...'
                              : 'Use This Location',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          backgroundColor: Theme.of(
                            context,
                          ).colorScheme.secondary,
                          foregroundColor: Theme.of(
                            context,
                          ).colorScheme.onSecondary,
                          disabledBackgroundColor: Theme.of(context)
                              .colorScheme
                              .onSurface
                              .withValues(alpha: 0.12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ],
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
