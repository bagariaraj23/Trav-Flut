import 'package:flutter/material.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/services/places_service.dart';
import 'package:tripthread/utils/debouncer.dart';
import 'package:tripthread/utils/place_search_cache.dart';

class PlaceSearchSheet extends StatefulWidget {
  final ScrollController controller;

  const PlaceSearchSheet({
    Key? key,
    required this.controller,
  }) : super(key: key);

  @override
  State<PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<PlaceSearchSheet> {
  final _searchController = TextEditingController();
  final _debouncer = Debouncer();
  final _placesService = PlacesService();

  List<Place> _searchResults = [];
  bool _isLoading = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _debouncer.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _searchController.text.trim();
    if (query.length < 2) {
      setState(() {
        _searchResults = [];
        _error = '';
      });
      return;
    }

    // Check cache first
    final cached = PlaceSearchCache.getResults(query);
    if (cached != null) {
      setState(() {
        _searchResults = cached;
        _error = '';
      });
      return;
    }

    // Debounce API call
    _debouncer.run(() async {
      if (!mounted) return;

      setState(() => _isLoading = true);

      try {
        final results = await _placesService.searchPlaces(query);
        if (mounted) {
          setState(() {
            _searchResults = results;
            _error = '';
            _isLoading = false;
          });
          // Cache results
          PlaceSearchCache.cacheResults(query, results);
        }
      } catch (e) {
        if (mounted) {
          setState(() {
            _error = 'Failed to search places. Please try again.';
            _isLoading = false;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Column(
        children: [
          AppBar(
            title: const Text('Select Location'),
            centerTitle: true,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search places...',
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                filled: true,
                fillColor: Theme.of(context).cardColor,
              ),
              textInputAction: TextInputAction.search,
            ),
          ),
          if (_error.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                _error,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
            ),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: CircularProgressIndicator(),
            ),
          Expanded(
            child: ListView.builder(
              controller: widget.controller,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _searchResults.length,
              itemBuilder: (context, index) {
                final place = _searchResults[index];
                return _buildPlaceItem(place);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceItem(Place place) {
    return ListTile(
      leading: const Icon(Icons.location_on_outlined),
      title: Text(place.name),
      subtitle: place.address != null ? Text(place.address!) : null,
      onTap: () => Navigator.of(context).pop(place),
    );
  }
}
