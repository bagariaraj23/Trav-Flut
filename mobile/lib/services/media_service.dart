import 'dart:async';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:mime/mime.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/app_permissions.dart';
import 'package:tripthread/utils/local_file_header.dart';
import 'package:tripthread/utils/multipart_xfile.dart';
import 'package:tripthread/utils/validators.dart';
import 'package:flutter/foundation.dart';

class MediaService {
  final ImagePicker _imagePicker = ImagePicker();
  final ApiService _apiService;
  final Dio _uploadClient;
  Future<void> _uploadQueue = Future.value();

  MediaService(this._apiService, {Dio? uploadClient})
      : _uploadClient = uploadClient ?? Dio();

  Future<bool> _allow(AppPermissionKind kind) async {
    final outcome = await AppPermissions.ensure(kind);
    if (outcome == AppPermissionOutcome.granted) return true;
    if (outcome == AppPermissionOutcome.permanentlyDenied) {
      throw AppPermissionException(AppPermissions.deniedMessage(kind));
    }
    return false;
  }

  Future<bool> _allowAny(List<AppPermissionKind> kinds) async {
    var blocked = false;
    for (final kind in kinds) {
      final outcome = await AppPermissions.ensure(kind);
      if (outcome == AppPermissionOutcome.granted) return true;
      if (outcome == AppPermissionOutcome.permanentlyDenied) blocked = true;
    }
    if (blocked) {
      throw AppPermissionException(AppPermissions.deniedMessage(kinds.first));
    }
    return false;
  }

  /// Pick an image from camera or gallery
  Future<XFile?> pickImage({bool fromCamera = false}) async {
    try {
      final allowed = await _allow(
        fromCamera ? AppPermissionKind.camera : AppPermissionKind.photos,
      );
      if (!allowed) return null;
      final XFile? pickedFile = await _imagePicker.pickImage(
        source: fromCamera ? ImageSource.camera : ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final validation = Validators.validateFile(
          pickedFile.name,
          await pickedFile.length(),
        );

        if (validation != null) {
          throw Exception(validation);
        }

        return pickedFile;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Pick a video file from gallery
  Future<XFile?> pickVideo() async {
    try {
      if (!await _allow(AppPermissionKind.videos)) return null;
      final XFile? pickedFile = await _imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(minutes: 10),
      );

      if (pickedFile != null) {
        final validation = Validators.validateFile(
          pickedFile.name,
          await pickedFile.length(),
        );

        if (validation != null) {
          throw Exception(validation);
        }

        return pickedFile;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  /// Pick any file type using image picker (limited to images and videos)
  Future<XFile?> pickFile({
    List<String>? allowedExtensions,
    bool allowMultiple = false,
  }) async {
    try {
      if (!await _allowAny([
        AppPermissionKind.photos,
        AppPermissionKind.videos,
      ])) {
        return null;
      }
      final XFile? pickedFile = await _imagePicker.pickMedia(
        imageQuality: 85,
      );

      if (pickedFile != null) {
        final validation = Validators.validateFile(
          pickedFile.name,
          await pickedFile.length(),
        );

        if (validation != null) {
          throw Exception(validation);
        }

        return pickedFile;
      }
      return null;
    } catch (e) {
      rethrow;
    }
  }

  Future<List<XFile>> pickMultipleMedia() async {
    try {
      if (!await _allowAny([
        AppPermissionKind.photos,
        AppPermissionKind.videos,
      ])) {
        return [];
      }
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'jpg',
          'jpeg',
          'png',
          'gif',
          'mp4',
          'mov',
          'avi'
        ],
      );

      if (result == null || result.files.isEmpty) {
        return [];
      }

      const maxSelection = 10;
      if (result.files.length > maxSelection) {
        throw Exception('You can select at most $maxSelection files at once.');
      }

      final files = <XFile>[];

      for (final file in result.files) {
        final pickedFile = file.xFile;
        final validation = Validators.validateFile(
          file.name,
          file.size,
        );

        if (validation != null) {
          throw Exception(validation);
        }

        files.add(pickedFile);
      }

      return files;
    } catch (e) {
      rethrow;
    }
  }

  /// Uploads a file to Cloudinary using a server-signed request.
  /// Confirms the upload with the backend to create a Media record.
  Future<Media?> uploadMediaToCloudinary({
    required XFile file,
    String? tripId,
    String usage = 'general',
    void Function(double progress)? onProgress,
  }) {
    return _enqueueUpload(() => _performUpload(
          file: file,
          tripId: tripId,
          usage: usage,
          onProgress: onProgress,
        ));
  }

  int _activeUploads = 0;
  static const maxConcurrentUploads = 3;

  Future<T> _enqueueUpload<T>(Future<T> Function() task) {
    final completer = Completer<T>();
    _uploadQueue = _uploadQueue.then((_) async {
      while (_activeUploads >= maxConcurrentUploads) {
        await Future.delayed(Duration(milliseconds: 100));
      }

      _activeUploads++;
      try {
        final result = await task();
        if (!completer.isCompleted) completer.complete(result);
      } catch (error, stackTrace) {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      } finally {
        _activeUploads--;
      }
    });
    return completer.future;
  }

  Future<Media?> _performUpload({
    required XFile file,
    String? tripId,
    String usage = 'general',
    void Function(double progress)? onProgress,
  }) async {
    String? uploadedPublicId;
    try {
      debugPrint(
          '[MediaService] Starting Cloudinary upload for file: ${file.path}');

      final filename = getFileName(file);
      final mediaType = getMediaType(file);
      final contentType = _inferMimeType(file, mediaType);

      onProgress?.call(0.0);

      // 1. Get Cloudinary signature from backend
      debugPrint('[MediaService] Getting Cloudinary signature...');
      final signatureResponse = await _apiService.getCloudinarySignature(
        filename: filename,
        contentType: contentType,
        tripId: tripId,
        usage: usage,
      );

      if (!signatureResponse.success || signatureResponse.data == null) {
        throw Exception(
            signatureResponse.error ?? 'Failed to get Cloudinary signature');
      }

      final uploadParams = Map<String, dynamic>.from(signatureResponse.data!);
      debugPrint('[MediaService] Got upload params: $uploadParams');

      // 2. Upload file directly to Cloudinary
      debugPrint('[MediaService] Uploading to Cloudinary...');
      final cloudinaryData = await _uploadToCloudinary(
        file: file,
        uploadParams: uploadParams,
        contentType: contentType,
        onProgress: (progress) {
          onProgress?.call(progress.clamp(0.0, 0.99));
        },
      );

      uploadedPublicId =
          (cloudinaryData['public_id'] as String?) ?? uploadParams['publicId'];

      final secureUrl = cloudinaryData['secure_url'] as String?;

      if (secureUrl == null || secureUrl.isEmpty) {
        if (uploadedPublicId != null) {
          await _cleanupFailedUpload(uploadedPublicId);
          uploadedPublicId = null;
        }
        throw Exception('Cloudinary upload did not return a secure URL');
      }

      debugPrint('[MediaService] Upload successful, secure URL: $secureUrl');

      // 3. Confirm upload with backend
      debugPrint('[MediaService] Confirming upload with backend...');
      final confirmResponse = await _apiService.confirmMediaUpload(
        url: (cloudinaryData['url'] as String?) ?? secureUrl,
        secureUrl: secureUrl,
        publicId: uploadedPublicId ?? uploadParams['publicId'],
        format: (cloudinaryData['format'] as String?) ??
            contentType.split('/').last,
        resourceType: (cloudinaryData['resource_type'] as String?) ??
            (mediaType == MediaType.image ? 'image' : 'video'),
        bytes: (cloudinaryData['bytes'] as int?) ?? await file.length(),
        originalFilename: filename,
        width: (cloudinaryData['width'] as num?)?.toInt(),
        height: (cloudinaryData['height'] as num?)?.toInt(),
        duration: cloudinaryData['duration'] as num?,
        tripId: tripId,
        usage: usage,
      );

      if (!confirmResponse.success || confirmResponse.data == null) {
        if (uploadedPublicId != null) {
          await _cleanupFailedUpload(uploadedPublicId);
          uploadedPublicId = null;
        }
        throw Exception(
            confirmResponse.error ?? 'Failed to confirm media upload');
      }

      debugPrint('[MediaService] Upload confirmation successful');
      onProgress?.call(1.0);
      return confirmResponse.data;
    } catch (e) {
      debugPrint('[MediaService] Error during media upload: $e');
      if (uploadedPublicId != null) {
        await _cleanupFailedUpload(uploadedPublicId);
        uploadedPublicId = null;
      }
      rethrow;
    }
  }

  /// Upload file directly to Cloudinary
  Future<Map<String, dynamic>> _uploadToCloudinary({
    required XFile file,
    required Map<String, dynamic> uploadParams,
    required String contentType,
    void Function(double progress)? onProgress,
  }) async {
    try {
      debugPrint(
          '[MediaService] Uploading to Cloudinary with params: $uploadParams');

      // Check if this is a mock response
      if (uploadParams['cloudName'] == 'test_cloud' ||
          uploadParams['apiKey'] == 'test_key') {
        debugPrint(
            '[MediaService] Mock mode detected, returning placeholder image');
        final placeholderUrl =
            'https://via.placeholder.com/400x300/007bff/ffffff?text=Test+Image';
        return {
          'secure_url': placeholderUrl,
          'url': placeholderUrl,
          'public_id': uploadParams['publicId'],
          'format': 'jpg',
          'resource_type': 'image',
          'bytes': await file.length(),
          'original_filename': getFileName(file),
        };
      }

      final uploadUrl = (uploadParams['uploadUrl'] as String?) ??
          'https://api.cloudinary.com/v1_1/${uploadParams['cloudName']}/auto/upload';

      const maxRetries = 2;
      var attempt = 0;

      while (true) {
        try {
          final formData = FormData.fromMap({
            'file': await multipartFromXFile(
              file,
              filename: getFileName(file),
              contentType: contentType,
            ),
            'api_key': uploadParams['apiKey'],
            'timestamp': uploadParams['timestamp'].toString(),
            'signature': uploadParams['signature'],
            'folder': uploadParams['folder'],
            'public_id': uploadParams['publicId'],
            if (uploadParams['uploadPreset'] != null)
              'upload_preset': uploadParams['uploadPreset'],
          });

          final response = await _uploadClient.post(
            uploadUrl,
            data: formData,
            options: Options(contentType: 'multipart/form-data'),
            onSendProgress: (sent, total) {
              if (total > 0) {
                onProgress?.call(sent / total);
              }
            },
          );

          if (response.statusCode == 200 && response.data != null) {
            final cloudinaryData = Map<String, dynamic>.from(response.data);
            debugPrint('[MediaService] Cloudinary upload successful');
            return cloudinaryData;
          }

          throw Exception('Cloudinary upload failed: ${response.data}');
        } on DioException catch (e) {
          final responseData = e.response?.data;
          debugPrint(
              '[MediaService] Error uploading to Cloudinary: ${e.message} | Response data: $responseData');
          if (attempt >= maxRetries) rethrow;
          attempt++;
          await Future.delayed(Duration(milliseconds: 500 * attempt));
        }
      }
    } catch (e) {
      debugPrint('[MediaService] Error uploading to Cloudinary: $e');
      rethrow;
    }
  }

  Future<void> _cleanupFailedUpload(String publicId) async {
    try {
      await _apiService.deleteMediaAsset(publicId);
    } catch (e) {
      debugPrint('[MediaService] Cleanup failed for $publicId: $e');
    }
  }

  /// Get media type from file
  MediaType getMediaType(XFile file) {
    final name = getFileName(file);
    try {
      final detectedMime = lookupMimeType(
        name,
        headerBytes: readLocalFileHeader(file.path),
      );
      if (detectedMime != null) {
        if (detectedMime.startsWith('image/')) {
          return MediaType.image;
        }
        if (detectedMime.startsWith('video/')) {
          return MediaType.video;
        }
      }
    } catch (e) {
      debugPrint(
          '[MediaService] MIME detection failed, falling back to extension: $e');
    }

    final extension = name.split('.').last.toLowerCase();

    if (['jpg', 'jpeg', 'png', 'gif'].contains(extension)) {
      return MediaType.image;
    } else if (['mp4', 'mov', 'avi'].contains(extension)) {
      return MediaType.video;
    } else {
      throw Exception('Unsupported file type');
    }
  }

  /// Get file size in bytes
  Future<int> getFileSize(XFile file) async {
    return await file.length();
  }

  /// Get file name
  String getFileName(XFile file) {
    if (file.name.isNotEmpty) return file.name;
    final parts = file.path.split(RegExp(r'[/\\]'));
    return parts.isEmpty ? file.path : parts.last;
  }

  String _inferMimeType(XFile file, MediaType mediaType) {
    final extension = getFileName(file).split('.').last.toLowerCase();

    if (mediaType == MediaType.image) {
      switch (extension) {
        case 'png':
          return 'image/png';
        case 'gif':
          return 'image/gif';
        case 'webp':
          return 'image/webp';
        default:
          return 'image/jpeg';
      }
    } else if (mediaType == MediaType.video) {
      switch (extension) {
        case 'mov':
          return 'video/quicktime';
        case 'avi':
          return 'video/x-msvideo';
        case 'm4v':
          return 'video/x-m4v';
        default:
          return 'video/mp4';
      }
    }

    throw Exception('Unsupported media type');
  }
}
