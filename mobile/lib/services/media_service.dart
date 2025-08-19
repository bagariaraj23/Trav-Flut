import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/utils/validators.dart';

class MediaService {
  final ImagePicker _imagePicker = ImagePicker();

  /// Pick an image from camera or gallery
  Future<File?> pickImage({bool fromCamera = false}) async {
    try {
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);

        // Validate the file
        final validation = Validators.validateFile(
          pickedFile.name,
          await file.length(),
        );

        if (validation != null) {
          throw Exception(validation);
        }

        return file;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Pick a video file from gallery
  Future<File?> pickVideo() async {
    try {
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10), // 10 minute limit
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);

        // Validate the file
        final validation = Validators.validateFile(
          pickedFile.name,
          await file.length(),
        );

        if (validation != null) {
          throw Exception(validation);
        }

        return file;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Pick any file type using image picker (limited to images and videos)
  Future<File?> pickFile({
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    try {
      // For simplicity, we'll use image picker for both images and videos
      // This avoids the file_picker compatibility issues
      final XFile? pickedFile = await _imagePicker.pickMedia(
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final file = File(pickedFile.path);

        // Validate the file
        final validation = Validators.validateFile(
          pickedFile.name,
          await file.length(),
        );

        if (validation != null) {
          throw Exception(validation);
        }

        return file;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Get media type from file
  MediaType getMediaType(File file) {
    final extension = file.path.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif'].contains(extension)) {
      return MediaType.image;
    } else if (['mp4', 'mov', 'avi'].contains(extension)) {
      return MediaType.video;
    } else {
      throw Exception('Unsupported file type');
    }
  }

  /// Get file size in bytes
  Future<int> getFileSize(File file) async {
    return await file.length();
  }

  /// Get file name
  String getFileName(File file) {
    return file.path.split('/').last;
  }
}
