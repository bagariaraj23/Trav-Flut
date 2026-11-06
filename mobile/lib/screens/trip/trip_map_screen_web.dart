import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/place_provider.dart';

/// Web stand-in for the native Mapbox trip map.
///
/// Lists the same places the mobile map would plot. The interactive map
/// stays on iOS and Android, where mapbox_maps_flutter is supported.
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
  List<MapPlace>? _places;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  Future<void> _loadPlaces() async {
    if (widget.initialPlaces != null) {
      setState(() {
        _places = widget.initialPlaces;
        _loading = false;
      });
      return;
    }

    final places = await context.read<PlaceProvider>().getTripPlaces(
      widget.tripId,
    );
    if (!mounted) return;
    setState(() {
      _places = places;
      _loading = false;
    });
  }

  String _originLabel(MapPlaceOrigin origin) {
    switch (origin) {
      case MapPlaceOrigin.destination:
        return 'Destination';
      case MapPlaceOrigin.threadEntry:
        return 'Shared';
      case MapPlaceOrigin.onTrip:
        return 'Visit';
    }
  }

  @override
  Widget build(BuildContext context) {
    final places = _places ?? const <MapPlace>[];
    return Scaffold(
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
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : places.isEmpty
          ? const Center(child: Text('No places on this trip yet.'))
          : ListView.separated(
              itemCount: places.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = places[index];
                final place = item.place;
                return ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(place.name),
                  subtitle: Text(
                    [
                      _originLabel(item.origin),
                      if (place.address != null && place.address!.isNotEmpty)
                        place.address!,
                      '${place.lat.toStringAsFixed(4)}, ${place.lng.toStringAsFixed(4)}',
                    ].join(' · '),
                  ),
                );
              },
            ),
    );
  }
}
