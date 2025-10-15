import 'package:flutter/material.dart';
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:geolocator/geolocator.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/place_provider.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:provider/provider.dart';

class MapPickerSheet extends StatefulWidget {
  final Function(Place place) onPlaceSelected;
  final String? initialPlaceName;
  final double? initialLat;
  final double? initialLng;

  const MapPickerSheet({
    super.key,
    required this.onPlaceSelected,
    this.initialPlaceName,
    this.initialLat,
    this.initialLng,
  });

  @override
  State<MapPickerSheet> createState() => _MapPickerSheetState();
}

class _MapPickerSheetState extends State<MapPickerSheet> {
  mapbox.MapboxMap? _mapboxMap;
  Position? _currentPosition;
  bool _loading = true;
  bool _error = false;
  String _errorMessage = '';

  mapbox.Point? _selectedPoint;
  String? _selectedName;

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    setState(() => _loading = true);

    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        throw Exception('Location services are disabled');
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Location permissions are denied');
        }
      }

      if (permission == LocationPermission.deniedForever) {
        throw Exception('Location permissions are permanently denied');
      }

      _currentPosition = await Geolocator.getCurrentPosition();
      setState(() => _loading = false);

      if (_mapboxMap != null) {
        await _mapboxMap!.flyTo(
          mapbox.CameraOptions(
            center: mapbox.Point(
              coordinates: mapbox.Position(
                widget.initialLng ?? _currentPosition!.longitude,
                widget.initialLat ?? _currentPosition!.latitude,
              ),
            ),
            zoom: 15.0,
          ),
          null,
        );
      }
    } catch (e) {
      setState(() {
        _loading = false;
        _error = true;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(context),
                    ),
                    const Expanded(
                      child: Text(
                        'Select Location',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(width: 48), // For symmetry
                  ],
                ),
              ),

              // Map
              Expanded(
                child: Stack(
                  children: [
                    if (_loading)
                      const Center(child: CircularProgressIndicator())
                    else if (_error)
                      Center(child: Text(_errorMessage))
                    else
                      mapbox.MapWidget(
                        key: const Key('mapWidget'),
                        onMapCreated: _onMapCreated,
                        onStyleLoadedListener: _onStyleLoaded,
                        onCameraChangeListener:
                            _onCameraChanged,
                      ),

                    // Center indicator
                    if (!_loading && !_error)
                      const Center(
                        child: Icon(
                          Icons.location_pin,
                          color: Colors.red,
                          size: 36,
                        ),
                      ),
                  ],
                ),
              ),

              // Bottom panel
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedPoint != null)
                      Text(
                        _selectedName ?? 'Selected Location',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed:
                          _selectedPoint != null ? _confirmLocation : null,
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                      ),
                      child: const Text('Use This Location'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
  }

  Future<void> _onStyleLoaded(mapbox.StyleLoadedEventData data) async {
    await _mapboxMap!.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(
            widget.initialLng ?? _currentPosition!.longitude,
            widget.initialLat ?? _currentPosition!.latitude,
          ),
        ),
        zoom: 15.0,
      ),
      null,
    );

    // Set initial selected point to current center
    final cameraState = await _mapboxMap!.getCameraState();
    setState(() {
      _selectedPoint = cameraState.center;
    });
  }

  // New camera change handler
  void _onCameraChanged(mapbox.CameraChangedEventData data) async {
    // Get current center coordinates when camera moves
    final cameraState = await _mapboxMap!.getCameraState();
    setState(() {
      _selectedPoint = cameraState.center;
    });
  }

  void _confirmLocation() async {
    if (_selectedPoint != null) {
      final placeProvider = context.read<PlaceProvider>();
      final place = Place(
        id: '', // Will be assigned by the backend
        name: widget.initialPlaceName ?? 'Selected Location',
        lat: _selectedPoint!.coordinates.lat.toDouble(), 
        lng: _selectedPoint!.coordinates.lng.toDouble(), 
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final resolvedPlace = await placeProvider.resolvePlace(place);
      if (resolvedPlace != null) {
        if (mounted) {
          widget.onPlaceSelected(resolvedPlace);
          Navigator.pop(context);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Failed to save location')),
          );
        }
      }
    }
  }
}
