import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:tripthread/models/place.dart';
import 'package:tripthread/providers/place_provider.dart';

class PlaceAutocompleteField extends StatefulWidget {
  final TextEditingController? controller;
  final Function(Place place) onPlaceSelected;
  final String? hintText;
  final String? labelText;
  final TextInputAction? textInputAction;
  final Function(String value)? onFieldSubmitted;
  final bool autofocus;
  final String? initialValue;
  final InputDecoration? decoration;

  const PlaceAutocompleteField({
    super.key,
    this.controller,
    required this.onPlaceSelected,
    this.hintText,
    this.labelText,
    this.textInputAction,
    this.onFieldSubmitted,
    this.autofocus = false,
    this.initialValue,
    this.decoration,
  });

  @override
  State<PlaceAutocompleteField> createState() => _PlaceAutocompleteFieldState();
}

class _PlaceAutocompleteFieldState extends State<PlaceAutocompleteField> {
  late TextEditingController _controller;
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ?? TextEditingController(text: widget.initialValue);
    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _showOverlay();
      } else {
        _hideOverlay();
      }
    });
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    _focusNode.dispose();
    _hideOverlay();
    super.dispose();
  }

  void _showOverlay() {
    if (_overlayEntry != null) return;

    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 5),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: Consumer<PlaceProvider>(
              builder: (context, placeProvider, _) {
                if (placeProvider.isSearching) {
                  return const Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Center(child: CircularProgressIndicator()),
                  );
                }

                if (placeProvider.searchError != null) {
                  return Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(placeProvider.searchError!),
                  );
                }

                return ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: placeProvider.searchResults.length,
                  itemBuilder: (context, index) {
                    final place = placeProvider.searchResults[index];
                    return ListTile(
                      title: Text(place.name),
                      subtitle:
                          place.address != null ? Text(place.address!) : null,
                      onTap: () {
                        _controller.text = place.name;
                        widget.onPlaceSelected(place);
                        _hideOverlay();
                        _focusNode.unfocus();
                      },
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _hideOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _onChanged(String value) {
    if (value.isEmpty) {
      context.read<PlaceProvider>().clearSearchResults();
      return;
    }

    context.read<PlaceProvider>().searchPlaces(value);
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextFormField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        textInputAction: widget.textInputAction,
        onFieldSubmitted: widget.onFieldSubmitted,
        autofocus: widget.autofocus,
        decoration: widget.decoration ??
            InputDecoration(
              hintText: widget.hintText ?? 'Search for a place...',
              labelText: widget.labelText,
              suffixIcon: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  _controller.clear();
                  context.read<PlaceProvider>().clearSearchResults();
                },
              ),
            ),
      ),
    );
  }
}
