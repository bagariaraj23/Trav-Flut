import 'package:flutter/foundation.dart';
import 'package:share_plus/share_plus.dart';
import 'package:tripthread/services/share_service.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/utils/error_handler.dart' as errors;

class ShareRecord {
  final String id;
  final String entityType;
  final String entityId;
  final String shareUrl;
  final String shareToken;
  final DateTime createdAt;

  const ShareRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.shareUrl,
    required this.shareToken,
    required this.createdAt,
  });
}

class ShareProvider extends ChangeNotifier {
  final ShareService _shareService;

  ShareProvider({
    required ShareService shareService,
  }) : _shareService = shareService;

  final List<ShareRecord> _userShares = [];
  final Map<String, bool> _isCreating = {};
  String? _error;

  List<ShareRecord> get userShares => List.unmodifiable(_userShares);
  String? get error => _error;
  bool isCreating(String entityId) => _isCreating[entityId] ?? false;

  Future<ShareLinkResult> createShare(String entityType, String entityId) async {
    final cacheKey = '$entityType:$entityId';

    if (_isCreating[cacheKey] == true) {
      throw errors.AppException('Share creation already in progress');
    }

    _isCreating[cacheKey] = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _shareService.createShare(entityType, entityId);

      final shareRecord = ShareRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        entityType: entityType,
        entityId: entityId,
        shareUrl: result.webUrl,
        shareToken: result.shareToken,
        createdAt: DateTime.now(),
      );

      _userShares.insert(0, shareRecord);
      _isCreating[cacheKey] = false;
      notifyListeners();

      return result;
    } catch (e) {
      _isCreating[cacheKey] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> openNativeShare(
    ShareLinkResult link, {
    String? subject,
    String? text,
  }) async {
    try {
      debugPrint('[ShareProvider] Opening native share with URL: ${link.webUrl}');

      final shareText = [
        if (text != null && text.isNotEmpty) text,
        link.webUrl,
        'Open in TripThread: ${link.primaryAppDeepLink}',
      ].join('\n\n');

      // Use share_plus to open the native share dialog
      await Share.share(
        shareText,
        subject: subject ?? 'Check this out on TripThread!',
      );

      debugPrint('[ShareProvider] Share dialog opened successfully');
    } catch (e) {
      debugPrint('[ShareProvider] openNativeShare error: $e');
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> resolveShare(String shareToken) async {
    try {
      final sharedEntity = await _shareService.resolveShare(shareToken);

      return {
        'entityType': sharedEntity.entityType,
        'entityId': sharedEntity.entityId,
        'entityData': sharedEntity.entityData,
        'shareData': sharedEntity.shareData,
      };
    } catch (e) {
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
