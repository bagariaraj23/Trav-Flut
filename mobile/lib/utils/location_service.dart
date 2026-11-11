import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:tripthread/utils/app_permissions.dart';

class LocationService {
  Future<Position?> getCurrentLocation() async {
    try {
      final access = await AppPermissions.ensure(AppPermissionKind.location);
      if (access != AppPermissionOutcome.granted) return null;

      return await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
        ),
      );
    } catch (e) {
      debugPrint('[LocationService] Error: $e');
      return null;
    }
  }
}