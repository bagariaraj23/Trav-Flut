import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:http_parser/http_parser.dart' as http_parser;
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/validators.dart';
import 'package:flutter/foundation.dart';

class MediaService {
  final ImagePicker _imagePicker = ImagePicker();
  final ApiService _apiService;
  final Dio _uploadClient;

  MediaService(this._apiService, {Dio? uploadClient})
      : _uploadClient = uploadClient ?? Dio();

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

  /// Uploads a file to Cloudinary using a server-signed request.
  /// Confirms the upload with the backend to create a Media record.
  Future<Media?> uploadMediaToCloudinary({
    required File file,
    String? tripId,
    String usage = 'general',
  }) async {
    try {
      debugPrint('[MediaService] Starting Cloudinary upload for file: ${file.path}');
      
      final filename = file.path.split('/').last;
      final mediaType = getMediaType(file);
      final contentType = _inferMimeType(file, mediaType);

      // 1. Get Cloudinary signature from backend
      debugPrint('[MediaService] Getting Cloudinary signature...');
      final signatureResponse = await _apiService.getCloudinarySignature(
        filename: filename,
        contentType: contentType,
        tripId: tripId,
        usage: usage,
      );

      if (!signatureResponse.success || signatureResponse.data == null) {
        throw Exception(signatureResponse.error ?? 'Failed to get Cloudinary signature');
      }

      final uploadParams =
          Map<String, dynamic>.from(signatureResponse.data!);
      debugPrint('[MediaService] Got upload params: $uploadParams');

      // 2. Upload file directly to Cloudinary
      debugPrint('[MediaService] Uploading to Cloudinary...');
      final cloudinaryData = await _uploadToCloudinary(
        file: file,
        uploadParams: uploadParams,
        contentType: contentType,
      );

      final secureUrl = cloudinaryData['secure_url'] as String?;

      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('Cloudinary upload did not return a secure URL');
      }

      debugPrint('[MediaService] Upload successful, secure URL: $secureUrl');

      // 3. Confirm upload with backend
      debugPrint('[MediaService] Confirming upload with backend...');
      final confirmResponse = await _apiService.confirmMediaUpload(
        url: (cloudinaryData['url'] as String?) ?? secureUrl,
        secureUrl: secureUrl,
        publicId: (cloudinaryData['public_id'] as String?) ?? uploadParams['publicId'],
        format: (cloudinaryData['format'] as String?) ?? contentType.split('/').last,
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
        throw Exception(confirmResponse.error ?? 'Failed to confirm media upload');
      }

      debugPrint('[MediaService] Upload confirmation successful');
      return confirmResponse.data;
    } catch (e) {
      debugPrint('[MediaService] Error during media upload: $e');
      rethrow;
    }
  }

  /// Upload file directly to Cloudinary
  Future<Map<String, dynamic>> _uploadToCloudinary({
    required File file,
    required Map<String, dynamic> uploadParams,
    required String contentType,
  }) async {
    try {
      debugPrint('[MediaService] Uploading to Cloudinary with params: $uploadParams');
      
      // Check if this is a mock response
      if (uploadParams['cloudName'] == 'test_cloud' || 
          uploadParams['apiKey'] == 'test_key') {
        debugPrint('[MediaService] Mock mode detected, returning placeholder image');
        final placeholderUrl = 'https://via.placeholder.com/400x300/007bff/ffffff?text=Test+Image';
        return {
          'secure_url': placeholderUrl,
          'url': placeholderUrl,
          'public_id': uploadParams['publicId'],
          'format': 'jpg',
          'resource_type': 'image',
          'bytes': await file.length(),
          'original_filename': file.path.split('/').last,
        };
      }

      final uploadUrl = (uploadParams['uploadUrl'] as String?) ??
          'https://api.cloudinary.com/v1_1/${uploadParams['cloudName']}/auto/upload';
      
      // Create multipart form data
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: file.path.split('/').last,
          contentType: http_parser.MediaType.parse(contentType),
        ),
        'api_key': uploadParams['apiKey'],
        'timestamp': uploadParams['timestamp'].toString(),
        'signature': uploadParams['signature'],
        'folder': uploadParams['folder'],
        'public_id': uploadParams['publicId'],
      });

      // Upload to Cloudinary
      final response = await _uploadClient.post(
        uploadUrl,
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
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
      rethrow;
    } catch (e) {
      debugPrint('[MediaService] Error uploading to Cloudinary: $e');
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

  String _inferMimeType(File file, MediaType mediaType) {
    final extension = file.path.split('.').last.toLowerCase();

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
