import 'package:tripthread/models/place.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/location_service.dart';

class PlacesService {
  final _api = ApiService();
  final _locationService = LocationService();

  Future<List<Place>> searchPlaces(String query, {int limit = 10}) async {
    try {
      // Get current location if available
      final location = await _locationService.getCurrentLocation();

      final response = await _api.searchPlaces(
          query: query,
          lat: location?.latitude,
          lng: location?.longitude,
          limit: limit);

      if (response.success && response.data != null) {
        return response.data ?? [];
      }

      return [];
    } catch (e) {
      print('[PlacesService] Search error: $e');
      return [];
    }
  }

  Future<Place?> resolvePlace({
    required String name,
    required double lat,
    required double lng,
    String? address,
    String? externalId,
    PlaceType? placeType,
    PlaceSource? source,
  }) async {
    try {
      final placeCandidate = Place(
        id: '',
        name: name,
        lat: lat,
        lng: lng,
        address: address,
        externalId: externalId,
        placeType: placeType ?? PlaceType.poi,
        source: source ?? PlaceSource.user,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      final response = await _api.resolvePlace(placeCandidate);

      if (response.success && response.data?.place != null) {
        return response.data!.place;
      }

      return null;
    } catch (e) {
      print('[PlacesService] Resolve error: $e');
      return null;
    }
  }
}
