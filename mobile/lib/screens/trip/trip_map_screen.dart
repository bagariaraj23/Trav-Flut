import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/place_provider.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:provider/provider.dart';

class TripMapScreen extends StatefulWidget {
  final String tripId;
  final String tripTitle;
  final List<PlaceOnTrip>? initialPlaces;

  const TripMapScreen({
    super.key,
    required this.tripId,
    required this.tripTitle,
    this.initialPlaces,
  });

  @override
  State<TripMapScreen> createState() => _TripMapScreenState();
}

class _TripMapScreenState extends State<TripMapScreen> {
  mapbox.MapboxMap? _mapboxMap;
  List<PlaceOnTrip>? _places;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    mapbox.MapboxOptions.setAccessToken(AppConfig.mapboxAccessToken);
    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    if (widget.initialPlaces != null) {
      setState(() {
        _places = widget.initialPlaces;
        _loading = false;
      });
    } else {
      try {
        final places = await context.read<PlaceProvider>().getTripPlaces(widget.tripId);
        setState(() {
          _places = places;
          _loading = false;
        });
      } catch (e) {
        setState(() {
          _error = 'Failed to load trip places: $e';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.tripTitle),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!))
              : Stack(
                  children: [
                    mapbox.MapWidget(
                      key: const Key('tripMapWidget'),
                      onMapCreated: _onMapCreated,
                    ),
                    if (_places != null && _places!.isNotEmpty)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: Container(
                          height: 100,
                          padding: const EdgeInsets.symmetric(vertical: 8.0),
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: _places!.length,
                            padding: const EdgeInsets.symmetric(horizontal: 16.0),
                            itemBuilder: (context, index) {
                              final place = _places![index].place;
                              return Card(
                                margin: const EdgeInsets.only(right: 8.0),
                                child: InkWell(
                                  onTap: () => _flyToPlace(place),
                                  child: Container(
                                    width: 200,
                                    padding: const EdgeInsets.all(8.0),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          place.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (place.address != null)
                                          Text(
                                            place.address!,
                                            style: Theme.of(context).textTheme.bodySmall,
                                            maxLines: 2,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                  ],
                ),
    );
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    if (_places != null && _places!.isNotEmpty) {
      // Calculate bounds
      double minLat = double.infinity;
      double maxLat = -double.infinity;
      double minLng = double.infinity;
      double maxLng = -double.infinity;

      for (final place in _places!) {
        final lat = place.place.lat;
        final lng = place.place.lng;

        minLat = lat < minLat ? lat : minLat;
        maxLat = lat > maxLat ? lat : maxLat;
        minLng = lng < minLng ? lng : minLng;
        maxLng = lng > maxLng ? lng : maxLng;

        // Add marker for each place
        final pointManager = await _mapboxMap?.annotations.createPointAnnotationManager();
        await pointManager?.create(mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(
            coordinates: mapbox.Position(lng, lat),
          ),
          textField: place.place.name,
        ));
      }

      // Fit map bounds to show all places
      await _mapboxMap?.flyTo(
        mapbox.CameraOptions(
          center: mapbox.Point(
            coordinates: mapbox.Position(
              (minLng + maxLng) / 2,
              (minLat + maxLat) / 2,
            ),
          ),
          zoom: _calculateZoomLevel(minLat, maxLat, minLng, maxLng),
          padding: mapbox.MbxEdgeInsets(
            top: 50,
            right: 50,
            bottom: 150,
            left: 50,
          ),
        ),
        mapbox.MapAnimationOptions(duration: 0, startDelay: 0),
      );
    }
  }

  double _calculateZoomLevel(double minLat, double maxLat, double minLng, double maxLng) {
    const zoomOffset = 0.5; // Zoom out a bit to show some context
    const minZoom = 2.0;
    const maxZoom = 18.0;

    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    // Simple logarithmic scale
    final zoom = -(math.log(maxDiff) / math.log(2)) + 8 - zoomOffset;

    return zoom.clamp(minZoom, maxZoom);
  }

  Future<void> _flyToPlace(Place place) async {
    await _mapboxMap?.flyTo(
      mapbox.CameraOptions(
        center: mapbox.Point(
          coordinates: mapbox.Position(place.lng, place.lat),
        ),
        zoom: 15,
      ),
      mapbox.MapAnimationOptions(duration: 500, startDelay: 0),
    );
  }

  @override
  void dispose() {
    _mapboxMap = null;
    super.dispose();
  }
}