import 'package:geocoding/geocoding.dart';
import 'package:tripthread/config/app_config.dart';

class PinLabel {
  final String title;
  final String? subtitle;

  const PinLabel({required this.title, this.subtitle});
}

const fallbackPinTitle = 'Selected location';

bool isFallbackPinTitle(String? name) {
  final value = name?.trim().toLowerCase();
  return value == null ||
      value.isEmpty ||
      value == 'selected location' ||
      value == 'unknown';
}

final Map<String, PinLabel> _pinLabelCache = {};

/// Neighborhood or street as the title, city as the second line.
/// Coordinates stay unused here; callers show them only when this fails.
Future<PinLabel> labelForPin(double lat, double lng) async {
  final key = '${lat.toStringAsFixed(4)},${lng.toStringAsFixed(4)}';
  final cached = _pinLabelCache[key];
  if (cached != null) return cached;

  try {
    final marks = await placemarkFromCoordinates(lat, lng);
    if (marks.isEmpty) {
      return const PinLabel(title: fallbackPinTitle);
    }
    final place = marks.first;
    final neighborhood = _first([
      place.subLocality,
      place.subAdministrativeArea,
    ]);
    final street = _first([place.thoroughfare, place.street, place.name]);
    final city = _first([
      place.locality,
      place.subAdministrativeArea,
      place.administrativeArea,
    ]);
    final title = neighborhood ?? street ?? city ?? fallbackPinTitle;
    final subtitleParts = <String>[];
    if (street != null && street != title) subtitleParts.add(street);
    if (city != null && city != title && !subtitleParts.contains(city)) {
      subtitleParts.add(city);
    }
    final region = _first([place.administrativeArea, place.country]);
    if (region != null && region != title && !subtitleParts.contains(region)) {
      subtitleParts.add(region);
    }
    final label = PinLabel(
      title: title,
      subtitle: subtitleParts.isEmpty ? null : subtitleParts.join(', '),
    );
    _pinLabelCache[key] = label;
    return label;
  } catch (_) {
    return const PinLabel(title: fallbackPinTitle);
  }
}

String? mapThumbnailUrl(double lat, double lng) {
  final token = AppConfig.mapboxAccessToken;
  if (token.isEmpty) return null;
  final lon = lng.toStringAsFixed(5);
  final latitude = lat.toStringAsFixed(5);
  return 'https://api.mapbox.com/styles/v1/mapbox/streets-v12/static/'
      'pin-s+1d6fe8($lon,$latitude)/$lon,$latitude,14,0/640x280@2x'
      '?access_token=$token';
}

String? _first(List<String?> values) {
  for (final value in values) {
    final trimmed = value?.trim();
    if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  }
  return null;
}
