import 'package:flutter/material.dart';
import 'dart:math' as math;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart' as mapbox;
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/place_provider.dart';
import 'package:tripthread/config/app_config.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

class TripMapScreen extends StatefulWidget {
  final String tripId;
  final String tripTitle;
  final List<MapPlace>? initialPlaces;

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
  static const String _mapStyleUri = 'mapbox://styles/mapbox/streets-v12';

  mapbox.MapboxMap? _mapboxMap;
  List<MapPlace>? _places;
  bool _loading = true;
  String? _error;
  mapbox.PolylineAnnotationManager? _routeManager;
  mapbox.CircleAnnotationManager? _circleManager;
  mapbox.PointAnnotationManager? _textManager;

  @override
  void initState() {
    super.initState();
    final token = AppConfig.mapboxAccessToken;
    if (token.isEmpty) {
      _loading = false;
      _error = 'Mapbox access token is not configured.';
      return;
    }
    mapbox.MapboxOptions.setAccessToken(token);
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
        final places = await context.read<PlaceProvider>().getTripPlaces(
          widget.tripId,
        );
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

  Color colorForOrigin(MapPlaceOrigin origin) {
    switch (origin) {
      case MapPlaceOrigin.destination:
        return Colors.red;
      case MapPlaceOrigin.threadEntry:
        return Colors.blue;
      case MapPlaceOrigin.onTrip:
        return Colors.green;
    }
  }

  IconData iconForOrigin(MapPlaceOrigin origin) {
    switch (origin) {
      case MapPlaceOrigin.destination:
        return Icons.flag;
      case MapPlaceOrigin.threadEntry:
        return Icons.location_on;
      case MapPlaceOrigin.onTrip:
        return Icons.add_location_alt;
    }
  }

  String labelForOrigin(MapPlaceOrigin origin) {
    switch (origin) {
      case MapPlaceOrigin.destination:
        return 'Destination';
      case MapPlaceOrigin.threadEntry:
        return 'Shared';
      case MapPlaceOrigin.onTrip:
        return 'Visit';
    }
  }

  Widget _buildLegendDialog() {
    return AlertDialog(
      title: const Text('Map Legend'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _legendItem(Colors.red, 'Destination', Icons.flag),
          const SizedBox(height: 8),
          _legendItem(Colors.green, 'Visited', Icons.add_location_alt),
          const SizedBox(height: 8),
          _legendItem(Colors.blue, 'Shared', Icons.location_on),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _legendItem(Color color, String label, IconData icon) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
        ),
        const SizedBox(width: 8),
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 14)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (context.canPop()) {
            context.pop();
          } else {
            context.go('/home');
          }
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.tripTitle),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
          actions: [
            // Legend button
            IconButton(
              icon: const Icon(Icons.info_outline),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => _buildLegendDialog(),
                );
              },
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error, size: 64, color: Colors.red[300]),
                    const SizedBox(height: 16),
                    Text(_error!),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Go Back'),
                    ),
                  ],
                ),
              )
            : _places == null || _places!.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.map_outlined,
                      size: 80,
                      color: Colors.grey.shade400,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'No locations yet',
                      style: TextStyle(fontSize: 18),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Share locations in the trip thread to see them here',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              )
            : Stack(
                children: [
                  // Map widget
                  mapbox.MapWidget(
                    key: const Key('tripMapWidget'),
                    styleUri: _mapStyleUri,
                    cameraOptions: mapbox.CameraOptions(
                      center: mapbox.Point(
                        coordinates: mapbox.Position(
                          _places!.first.place.lng,
                          _places!.first.place.lat,
                        ),
                      ),
                      zoom: 12.0,
                    ),
                    onMapCreated: _onMapCreated,
                  ),

                  // Place cards at bottom (ONLY ONE LIST)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 130,
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _places!.length,
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, idx) {
                          final mp = _places![idx];
                          return _buildPlaceCard(mp);
                        },
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPlaceCard(MapPlace mapPlace) {
    final place = mapPlace.place;
    final color = colorForOrigin(mapPlace.origin);
    final label = labelForOrigin(mapPlace.origin);
    final icon = iconForOrigin(mapPlace.origin);

    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 180, maxWidth: 280),
      child: Card(
        elevation: 4,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: InkWell(
          onTap: () => _flyToPlace(place),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              // mainAxisSize: MainAxisSize.min,
              children: [
                // Origin badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                      color: color.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon, size: 12, color: color),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          label,
                          style: TextStyle(
                            fontSize: 10,
                            color: color,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // Place name - dynamic sizing
                Expanded(
                  flex: 1,
                  child: Text(
                    place.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      height: 1.2,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

                // Address - only show if space available
                if (place.address != null && place.address!.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 1,
                    child: Text(
                      place.address!,
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                // Notes - only show if space available and no address
                if (mapPlace.notes != null &&
                    mapPlace.notes!.isNotEmpty &&
                    (place.address == null || place.address!.isEmpty)) ...[
                  const SizedBox(height: 4),
                  Expanded(
                    flex: 1, // Also gets 1/3 of the space
                    child: Text(
                      mapPlace.notes!,
                      style: TextStyle(
                        fontSize: 10,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _onMapCreated(mapbox.MapboxMap mapboxMap) {
    _mapboxMap = mapboxMap;
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    if (_places == null || _places!.isEmpty) return;

    // Sort places properly - destinations LAST, others chronologically
    final sortedPlaces = List<MapPlace>.from(_places!);

    sortedPlaces.sort((a, b) {
      // STEP 1: Destinations always come LAST (at the end of the route)
      if (a.origin == MapPlaceOrigin.destination &&
          b.origin != MapPlaceOrigin.destination) {
        return 1;
      }
      if (b.origin == MapPlaceOrigin.destination &&
          a.origin != MapPlaceOrigin.destination) {
        return -1;
      }
      // STEP 2: If both are destinations, sort by destinationIndex
      if (a.origin == MapPlaceOrigin.destination &&
          b.origin == MapPlaceOrigin.destination) {
        final indexA = a.destinationIndex ?? 0;
        final indexB = b.destinationIndex ?? 0;
        return indexA.compareTo(indexB);
      }

      // STEP 3: For non-destinations, sort chronologically
      final timeA = a.visitedAt ?? a.createdAt ?? DateTime(1970);
      final timeB = b.visitedAt ?? b.createdAt ?? DateTime(1970);
      return timeA.compareTo(timeB);
    });

    debugPrint('[TripMapScreen] Sorted places order:');
    for (int i = 0; i < sortedPlaces.length; i++) {
      final mp = sortedPlaces[i];
      debugPrint('  $i. ${mp.place.name} - Origin: ${mp.origin}');
    }

    double minLat = double.infinity;
    double maxLat = -double.infinity;
    double minLng = double.infinity;
    double maxLng = -double.infinity;

    // Initialize managers
    _circleManager ??= await _mapboxMap?.annotations
        .createCircleAnnotationManager();
    _textManager ??= await _mapboxMap?.annotations
        .createPointAnnotationManager();
    _routeManager ??= await _mapboxMap?.annotations
        .createPolylineAnnotationManager();

    // Create markers
    for (final mapPlace in sortedPlaces) {
      final place = mapPlace.place;
      final lat = place.lat;
      final lng = place.lng;

      minLat = lat < minLat ? lat : minLat;
      maxLat = lat > maxLat ? lat : maxLat;
      minLng = lng < minLng ? lng : minLng;
      maxLng = lng > maxLng ? lng : maxLng;

      final color = colorForOrigin(mapPlace.origin);

      // Circle marker
      await _circleManager?.create(
        mapbox.CircleAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
          circleColor: color.toARGB32(),
          circleRadius: 10.0,
          circleStrokeWidth: 2.0,
          circleStrokeColor: Colors.white.toARGB32(),
        ),
      );

      // Text label
      await _textManager?.create(
        mapbox.PointAnnotationOptions(
          geometry: mapbox.Point(coordinates: mapbox.Position(lng, lat)),
          textField: place.name,
          textColor: Colors.black.toARGB32(),
          textHaloColor: Colors.white.toARGB32(),
          textHaloWidth: 2.0,
          textSize: 12.0,
          textOffset: [0, 1.5],
        ),
      );
    }

    // Draw route
    if (sortedPlaces.length > 1) {
      await _drawChronologicalRoute(sortedPlaces);
    }

    // FIT BOUNDS - Auto-zoom to show all places
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
          top: 60,
          right: 40,
          bottom: 160,
          left: 40,
        ),
      ),
      mapbox.MapAnimationOptions(duration: 1000, startDelay: 0),
    );
  }

  // Draw route polyline
  Future<void> _drawChronologicalRoute(List<MapPlace> sortedPlaces) async {
    // Map to Position objects
    final coordinates = sortedPlaces
        .map((mp) => mapbox.Position(mp.place.lng, mp.place.lat))
        .toList();

    // Use coordinates directly, don't map again!
    await _routeManager?.create(
      mapbox.PolylineAnnotationOptions(
        geometry: mapbox.LineString(coordinates: coordinates),
        lineColor: Colors.deepPurple.toARGB32(),
        lineWidth: 4.0,
        lineOpacity: 0.7,
      ),
    );

    debugPrint('[TripMapScreen] Route drawn with ${coordinates.length} points');
  }

  double _calculateZoomLevel(
    double minLat,
    double maxLat,
    double minLng,
    double maxLng,
  ) {
    const zoomOffset = 0.8;
    const minZoom = 2.0;
    const maxZoom = 16.0;

    final latDiff = maxLat - minLat;
    final lngDiff = maxLng - minLng;
    final maxDiff = latDiff > lngDiff ? latDiff : lngDiff;

    if (maxDiff == 0) return 14.0; // Single location

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
    try {
      _routeManager?.deleteAll();
      _circleManager?.deleteAll();
      _textManager?.deleteAll();
    } catch (_) {}
    _mapboxMap = null;
    super.dispose();
  }
}
