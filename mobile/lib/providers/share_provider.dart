import 'package:flutter/foundation.dart';
import 'package:tripthread/services/share_service.dart';
import 'package:tripthread/services/deep_link_service.dart';
import 'package:tripthread/utils/error_handler.dart';
import 'package:tripthread/utils/error_handler.dart' as errors;

class ShareRecord {
  final String id;
  final String entityType;
  final String entityId;
  final String shareUrl;
  final DateTime createdAt;

  const ShareRecord({
    required this.id,
    required this.entityType,
    required this.entityId,
    required this.shareUrl,
    required this.createdAt,
  });
}

class ShareProvider extends ChangeNotifier {
  final ShareService _shareService;
  final DeepLinkService _deepLinkService;

  ShareProvider({
    required ShareService shareService,
    required DeepLinkService deepLinkService,
  })  : _shareService = shareService,
        _deepLinkService = deepLinkService;

  final List<ShareRecord> _userShares = [];
  final Map<String, bool> _isCreating = {};
  String? _error;

  List<ShareRecord> get userShares => List.unmodifiable(_userShares);
  String? get error => _error;
  bool isCreating(String entityId) => _isCreating[entityId] ?? false;

  Future<String> createShare(
    String entityType,
    String entityId,
  ) async {
    final cacheKey = '$entityType:$entityId';

    if (_isCreating[cacheKey] == true) {
      throw errors.AppException('Share creation already in progress');
    }

    _isCreating[cacheKey] = true;
    _error = null;
    notifyListeners();

    try {
      final shareUrl = await _shareService.createShare(entityType, entityId);

      final shareRecord = ShareRecord(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        entityType: entityType,
        entityId: entityId,
        shareUrl: shareUrl,
        createdAt: DateTime.now(),
      );

      _userShares.insert(0, shareRecord);
      _isCreating[cacheKey] = false;
      notifyListeners();

      return shareUrl;
    } catch (e) {
      _isCreating[cacheKey] = false;
      _error = ErrorHandler.handleError(e).message;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> openNativeShare(String shareUrl) async {
    try {
      // Use platform channel or share_plus package
      // For now, just log - UI layer will handle native share
      debugPrint('[ShareProvider] Share URL: $shareUrl');
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

