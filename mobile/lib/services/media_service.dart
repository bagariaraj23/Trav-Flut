import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/utils/validators.dart';
import 'package:flutter/foundation.dart';

class MediaService {
  final ImagePicker _imagePicker = ImagePicker();
  final ApiService _apiService;

  MediaService(this._apiService);

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
  Future<Media?> uploadMediaToCloudinary(
    File file, 
    String tripId, 
    {String? threadEntryId}
  ) async {
    try {
      debugPrint('[MediaService] Starting Cloudinary upload for file: ${file.path}');
      
      final filename = file.path.split('/').last;
      final contentType = getMediaType(file) == MediaType.image ? 'image/jpeg' : 'video/mp4';
      final resourceType = getMediaType(file) == MediaType.image ? 'image' : 'video';

      // 1. Get Cloudinary signature from backend
      debugPrint('[MediaService] Getting Cloudinary signature...');
      final signatureResponse = await _apiService.getCloudinarySignature(
        tripId: tripId,
        filename: filename,
        resourceType: resourceType,
      );

      if (!signatureResponse.success || signatureResponse.data == null) {
        throw Exception(signatureResponse.error ?? 'Failed to get Cloudinary signature');
      }

      final uploadParams = signatureResponse.data!['uploadParams'] as Map<String, dynamic>;
      debugPrint('[MediaService] Got upload params: $uploadParams');

      // 2. Upload file directly to Cloudinary
      debugPrint('[MediaService] Uploading to Cloudinary...');
      final cloudinaryUrl = await _uploadToCloudinary(file, uploadParams);

      if (cloudinaryUrl == null) {
        throw Exception('Failed to upload to Cloudinary');
      }

      debugPrint('[MediaService] Upload successful, URL: $cloudinaryUrl');

      // 3. Confirm upload with backend
      debugPrint('[MediaService] Confirming upload with backend...');
      final confirmResponse = await _apiService.confirmMediaUpload(
        url: cloudinaryUrl,
        secureUrl: cloudinaryUrl,
        publicId: uploadParams['public_id'],
        format: uploadParams['format'] ?? 'jpg',
        resourceType: uploadParams['resource_type'] ?? 'image',
        bytes: await file.length(),
        originalFilename: filename,
        tripId: tripId,
        threadEntryId: threadEntryId,
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
  Future<String?> _uploadToCloudinary(
    File file, 
    Map<String, dynamic> uploadParams
  ) async {
    try {
      debugPrint('[MediaService] Uploading to Cloudinary with params: $uploadParams');
      
      // Check if this is a mock response
      if (uploadParams['cloud_name'] == 'test_cloud' || 
          uploadParams['api_key'] == 'test_key') {
        debugPrint('[MediaService] Mock mode detected, returning placeholder image');
        return 'https://via.placeholder.com/400x300/007bff/ffffff?text=Test+Image';
      }

      final uploadUrl = 'https://api.cloudinary.com/v1_1/${uploadParams['cloud_name']}/auto/upload';
      
      // Create multipart form data
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(file.path, filename: file.path.split('/').last),
        'api_key': uploadParams['api_key'],
        'timestamp': uploadParams['timestamp'],
        'signature': uploadParams['signature'],
        'folder': uploadParams['folder'],
        'public_id': uploadParams['public_id'],
        'resource_type': uploadParams['resource_type'],
        'overwrite': uploadParams['overwrite'] ?? true,
      });

      // Upload to Cloudinary
      final response = await Dio().post(uploadUrl, data: formData);

      if (response.statusCode == 200 && response.data != null) {
        final cloudinaryData = response.data as Map<String, dynamic>;
        final secureUrl = cloudinaryData['secure_url'] as String?;
        
        if (secureUrl != null) {
          debugPrint('[MediaService] Cloudinary upload successful: $secureUrl');
          return secureUrl;
        }
      }

      throw Exception('Cloudinary upload failed: ${response.data}');
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
}
