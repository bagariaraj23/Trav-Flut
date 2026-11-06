import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

enum AppPermissionKind { location, camera, photos, videos }

enum AppPermissionOutcome { granted, denied, permanentlyDenied }

class AppPermissionInfo {
  final AppPermissionKind kind;
  final String title;
  final String dataUse;
  final IconData icon;

  const AppPermissionInfo({
    required this.kind,
    required this.title,
    required this.dataUse,
    required this.icon,
  });
}

class AppPermissionException implements Exception {
  final String message;
  const AppPermissionException(this.message);

  @override
  String toString() => message;
}

class AppPermissions {
  static const details = <AppPermissionInfo>[
    AppPermissionInfo(
      kind: AppPermissionKind.location,
      title: 'Location',
      icon: Icons.place_outlined,
      dataUse:
          'Used while the map is open, to center on where you are and to save a place you confirm on a trip. TripThread does not track your location in the background.',
    ),
    AppPermissionInfo(
      kind: AppPermissionKind.camera,
      title: 'Camera',
      icon: Icons.photo_camera_outlined,
      dataUse:
          'Used only when you take a photo for a trip, a cover, or your profile. That photo is uploaded with the post.',
    ),
    AppPermissionInfo(
      kind: AppPermissionKind.photos,
      title: 'Photos',
      icon: Icons.photo_library_outlined,
      dataUse:
          'Used when you choose a photo to attach. TripThread reads the photo you pick, not the rest of your library.',
    ),
    AppPermissionInfo(
      kind: AppPermissionKind.videos,
      title: 'Videos',
      icon: Icons.video_library_outlined,
      dataUse:
          'Used when you choose a video to attach. TripThread reads the video you pick, not the rest of your library.',
    ),
  ];

  static Future<PermissionStatus> status(AppPermissionKind kind) {
    return _permission(kind).status;
  }

  static Future<AppPermissionOutcome> ensure(AppPermissionKind kind) async {
    final permission = _permission(kind);
    var current = await permission.status;
    if (_allowed(current)) return AppPermissionOutcome.granted;
    if (current.isPermanentlyDenied || current.isRestricted) {
      return AppPermissionOutcome.permanentlyDenied;
    }
    current = await permission.request();
    if (_allowed(current)) return AppPermissionOutcome.granted;
    if (current.isPermanentlyDenied || current.isRestricted) {
      return AppPermissionOutcome.permanentlyDenied;
    }
    return AppPermissionOutcome.denied;
  }

  static Future<bool> openSettings() => openAppSettings();

  static String deniedMessage(AppPermissionKind kind) {
    final name = details.firstWhere((item) => item.kind == kind).title;
    return '$name access is turned off for TripThread. You can allow it in Settings.';
  }

  static Permission _permission(AppPermissionKind kind) {
    switch (kind) {
      case AppPermissionKind.location:
        return Permission.locationWhenInUse;
      case AppPermissionKind.camera:
        return Permission.camera;
      case AppPermissionKind.photos:
        return Permission.photos;
      case AppPermissionKind.videos:
        return defaultTargetPlatform == TargetPlatform.iOS
            ? Permission.photos
            : Permission.videos;
    }
  }

  static bool _allowed(PermissionStatus status) =>
      status.isGranted || status.isLimited;
}
