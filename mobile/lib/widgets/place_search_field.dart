import 'package:flutter/material.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/models/place.dart';

class PlaceSearchField extends StatefulWidget {
  final TextEditingController controller;
  final String? initialValue;
  final Function(Place) onPlaceSelected;
  final String label;
  final String hint;
  final PlaceType? placeType;
  final double? latitude;
  final double? longitude;

  const PlaceSearchField({
    super.key,
    required this.controller,
    this.initialValue,
    required this.onPlaceSelected,
    this.label = 'Location',
    this.hint = 'Search for a place...',
    this.placeType,
    this.latitude,
    this.longitude,
  });

  @override
  State<PlaceSearchField> createState() => _PlaceSearchFieldState();
}

class _PlaceSearchFieldState extends State<PlaceSearchField> {
  final _apiService = ApiService();
  List<Place> _suggestions = [];
  bool _isLoading = false;
  String _lastQuery = '';

  @override
  void initState() {
    super.initState();
    if (widget.initialValue != null) {
      widget.controller.text = widget.initialValue!;
    }
  }

  Future<void> _searchPlaces(String query) async {
    if (query.trim().isEmpty || query == _lastQuery) {
      return;
    }

    _lastQuery = query;
    setState(() {
      _isLoading = true;
    });

    try {
      final response = await _apiService.searchPlaces(
        query: query,
        lat: widget.latitude,
        lng: widget.longitude,
        placeType: widget.placeType?.toString(),
      );

      if (response.success && response.data != null) {
        setState(() {
          _suggestions = response.data!;
        });
      }
    } catch (e) {
      debugPrint('Error searching places: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error searching places: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Place>(
      initialValue: TextEditingValue(text: widget.initialValue ?? ''),
      displayStringForOption: (Place option) => option.name,
      optionsBuilder: (TextEditingValue textEditingValue) async {
        if (textEditingValue.text.isEmpty) {
          return const Iterable<Place>.empty();
        }
        await _searchPlaces(textEditingValue.text);
        return _suggestions;
      },
      onSelected: (Place place) {
        widget.controller.text = place.name;
        widget.onPlaceSelected(place);
      },
      fieldViewBuilder: (BuildContext context,
          TextEditingController fieldTextController,
          FocusNode fieldFocusNode,
          VoidCallback onFieldSubmitted) {
        return TextFormField(
          controller: fieldTextController,
          focusNode: fieldFocusNode,
          decoration: InputDecoration(
            labelText: widget.label,
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.location_on),
            suffixIcon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : fieldTextController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          fieldTextController.clear();
                          setState(() {
                            _suggestions = [];
                            _lastQuery = '';
                          });
                        },
                      )
                    : null,
          ),
        );
      },
      optionsViewBuilder: (BuildContext context,
          AutocompleteOnSelected<Place> onSelected, Iterable<Place> options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4.0,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(context).size.height * 0.3,
                maxWidth: MediaQuery.of(context).size.width * 0.9,
              ),
              child: ListView.builder(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (BuildContext context, int index) {
                  final place = options.elementAt(index);
                  return InkWell(
                    onTap: () {
                      onSelected(place);
                    },
                    child: Container(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        children: [
                          Icon(
                            _getIconForPlaceType(place.placeType),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  place.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (place.address != null)
                                  Text(
                                    place.address!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _getIconForPlaceType(PlaceType type) {
    switch (type) {
      case PlaceType.stay:
        return Icons.hotel;
      case PlaceType.food:
        return Icons.restaurant;
      case PlaceType.transport:
        return Icons.directions_bus;
      case PlaceType.viewpoint:
        return Icons.landscape;
      case PlaceType.poi:
        return Icons.location_on;
      case PlaceType.other:
        return Icons.place;
    }
  }
}
