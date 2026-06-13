import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tripthread/models/chat_conversation.dart';
import 'package:tripthread/models/chat_message.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/chat_socket_service.dart';
import 'package:tripthread/services/storage_service.dart';

class ChatProvider with ChangeNotifier {
  final ApiService _apiService;
  final StorageService _storageService;
  late final ChatSocketService _socketService;

  List<ChatConversationSummary> _conversations = [];
  final Map<String, List<ChatMessageModel>> _messagesByConversation = {};
  final Map<String, String?> _nextCursorByConversation = {};
  final Map<String, bool> _hasMoreByConversation = {};
  bool _loadingConversations = false;
  final Map<String, bool> _loadingMessages = {};
  String? _error;
  // conversationId -> (userId -> typing-until time)
  final Map<String, Map<String, DateTime>> _typingByConversation = {};
  Timer? _typingExpiryTimer;
  DateTime? _lastTypingSentAt;
  static const _typingThrottleMs = 250;

  List<ChatConversationSummary> get conversations => List.unmodifiable(_conversations);
  String? get error => _error;
  bool get loadingConversations => _loadingConversations;

  ChatProvider({
    required ApiService apiService,
    required StorageService storageService,
  })  : _apiService = apiService,
        _storageService = storageService {
    _socketService = ChatSocketService(
      getAccessToken: () => _storageService.getAccessToken(),
    );
    _socketService.onMessageNew = _onMessageNew;
    _socketService.onMessageUpdated = _onMessageUpdated;
    _socketService.onMessageDeleted = _onMessageDeleted;
    _socketService.onTyping = _onTyping;
    _socketService.onConnected = (_) => notifyListeners();
    _socketService.onError = (msg) {
      _error = msg;
      notifyListeners();
    };
    // Socket is opened from [onAuthSignedIn] / [connectSocket] so it does not race token restore or [resetConnection].
  }

  void connectSocket() {
    // Socket is started in the constructor; keep this for backward compatibility.
    if (!_socketService.isConnected) {
      _socketService.connect();
    }
  }

  /// Call when the user becomes authenticated (e.g. after login). Opens WebSocket with new tokens.
  void onAuthSignedIn() {
    _socketService.resetConnection();
    _socketService.connect();
  }

  /// Call when the user logs out. Closes WebSocket; [connect] will work again after next sign-in.
  void onAuthSignedOut() {
    _socketService.resetConnection();
  }

  void disconnectSocket() {
    // Intentionally left as a no-op so chat stays real-time while app is running.
  }

  void _onMessageNew(String conversationId, ChatMessageModel message) {
    final list = _messagesByConversation[conversationId] ?? [];
    final existingIndex = list.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      // If a message with same id arrives again (e.g. edit back-compat event),
      // replace it so content stays in sync across clients.
      final updated = [...list];
      updated[existingIndex] = message;
      _messagesByConversation[conversationId] = updated;
    } else {
      _messagesByConversation[conversationId] = [message, ...list];
    }
    if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
      HapticFeedback.lightImpact();
    }
    notifyListeners();
  }

  void _onTyping(String conversationId, String userId, String untilIso) {
    try {
      final until = DateTime.tryParse(untilIso);
      if (until == null) return;
      final now = DateTime.now();
      if (!until.isAfter(now)) return;
      final existing = _typingByConversation[conversationId] ?? <String, DateTime>{};
      existing[userId] = until;
      _typingByConversation[conversationId] = existing;
      _startTypingExpiryTimer();
      notifyListeners();
    } catch (_) {
      // ignore parse errors
    }
  }

  void _onMessageUpdated(String conversationId, ChatMessageModel updated) {
    final list = _messagesByConversation[conversationId];
    if (list == null || list.isEmpty) return;
    _messagesByConversation[conversationId] =
        list.map((m) => m.id == updated.id ? updated : m).toList();
    notifyListeners();
  }

  void _onMessageDeleted(String conversationId, String messageId, String deletedAt) {
    final list = _messagesByConversation[conversationId];
    if (list == null || list.isEmpty) return;
    _messagesByConversation[conversationId] = list
        .map((m) => m.id == messageId
            ? m.copyWith(
                content: '',
                deletedAt: deletedAt,
                attachments: const [],
                replyTo: null,
              )
            : m)
        .toList();
    notifyListeners();
  }

  void _startTypingExpiryTimer() {
    _typingExpiryTimer?.cancel();
    _typingExpiryTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      bool changed = false;
      final now = DateTime.now();
      for (final entry in _typingByConversation.entries.toList()) {
        final active = entry.value.entries.where((e) => e.value.isAfter(now)).toList();
        if (active.length != entry.value.length) {
          if (active.isEmpty) {
            _typingByConversation.remove(entry.key);
          } else {
            _typingByConversation[entry.key] = { for (final e in active) e.key: e.value };
          }
          changed = true;
        }
      }
      if (changed) notifyListeners();
      final hasAny = _typingByConversation.isNotEmpty;
      if (!hasAny) {
        _typingExpiryTimer?.cancel();
        _typingExpiryTimer = null;
      }
    });
  }

  List<ChatMessageModel> getMessages(String conversationId) {
    return List.unmodifiable(_messagesByConversation[conversationId] ?? []);
  }

  List<String> getTypingUsers(String conversationId) {
    final map = _typingByConversation[conversationId];
    if (map == null || map.isEmpty) return [];
    final now = DateTime.now();
    final activeEntries = map.entries.where((e) => e.value.isAfter(now)).toList();
    // cleanup expired
    _typingByConversation[conversationId] = {
      for (final e in activeEntries) e.key: e.value,
    };
    return activeEntries.map((e) => e.key).toList();
  }

  bool isLoadingMessages(String conversationId) => _loadingMessages[conversationId] ?? false;
  String? getNextCursor(String conversationId) => _nextCursorByConversation[conversationId];
  bool hasMoreMessages(String conversationId) => _hasMoreByConversation[conversationId] ?? false;

  Future<void> loadConversations({String? tripId}) async {
    _loadingConversations = true;
    _error = null;
    notifyListeners();
    final res = await _apiService.getChatConversations(tripId: tripId);
    _loadingConversations = false;
    if (res.success && res.data != null) {
      _conversations = res.data!;
    } else {
      _error = res.error;
    }
    notifyListeners();
  }

  Future<bool> loadMessages(String conversationId, {bool loadMore = false}) async {
    if (_loadingMessages[conversationId] == true) return false;
    _loadingMessages[conversationId] = true;
    notifyListeners();
    final before = loadMore ? _nextCursorByConversation[conversationId] : null;
    final res = await _apiService.getChatMessages(conversationId, limit: 30, before: before);
    _loadingMessages[conversationId] = false;
    if (res.success && res.data != null) {
      final p = res.data!;
      if (loadMore) {
        final existing = _messagesByConversation[conversationId] ?? [];
        _messagesByConversation[conversationId] = [...existing, ...p.messages];
      } else {
        _messagesByConversation[conversationId] = List.from(p.messages);
      }
      _nextCursorByConversation[conversationId] = p.nextCursor;
      _hasMoreByConversation[conversationId] = p.hasMore;
      notifyListeners();
      return true;
    }
    notifyListeners();
    return false;
  }

  Future<bool> sendMessage(String conversationId, String content,
      {String? replyToMessageId, List<String>? attachmentMediaIds}) async {
    final res = await _apiService.sendChatMessage(
      conversationId,
      content: content,
      replyToMessageId: replyToMessageId,
      attachmentMediaIds: attachmentMediaIds,
    );
    if (res.success && res.data != null) {
      _onMessageNew(conversationId, res.data!);
      if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
        HapticFeedback.lightImpact();
      }
      return true;
    }
    _error = res.error;
    notifyListeners();
    return false;
  }

  Future<bool> deleteMessage(String conversationId, String messageId) async {
    final res = await _apiService.deleteChatMessage(conversationId, messageId);
    if (res.success && res.data != null) {
      final deleted = res.data!;
      _onMessageDeleted(
        conversationId,
        deleted.id,
        deleted.deletedAt ?? DateTime.now().toUtc().toIso8601String(),
      );
      return true;
    }
    _error = res.error;
    notifyListeners();
    return false;
  }

  Future<bool> editMessage(
    String conversationId,
    String messageId, {
    required String content,
  }) async {
    final res = await _apiService.editChatMessage(
      conversationId,
      messageId,
      content: content,
    );
    if (res.success && res.data != null) {
      _onMessageUpdated(conversationId, res.data!);
      return true;
    }
    _error = res.error;
    notifyListeners();
    return false;
  }

  Future<void> markRead(String conversationId) async {
    await _apiService.markChatConversationRead(conversationId);
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx >= 0) {
      await loadConversations();
    }
  }

  Future<ChatConversationSummary?> createConversation({
    required String type,
    required List<String> participantIds,
    String? name,
    String? tripId,
  }) async {
    final res = await _apiService.createChatConversation(
      type: type,
      participantIds: participantIds,
      name: name,
      tripId: tripId,
    );
    if (res.success && res.data != null) {
      _conversations.insert(0, res.data!);
      notifyListeners();
      return res.data;
    }
    _error = res.error;
    notifyListeners();
    return null;
  }

  void sendTyping(String conversationId) {
    final now = DateTime.now();
    if (_lastTypingSentAt != null &&
        now.difference(_lastTypingSentAt!).inMilliseconds < _typingThrottleMs) {
      return;
    }
    _lastTypingSentAt = now;
    _socketService.sendTyping(conversationId);
  }

  Future<bool> updateGroupInfo(String conversationId, {String? name, String? avatarUrl}) async {
    final res = await _apiService.updateGroupSettings(conversationId, name: name, avatarUrl: avatarUrl);
    if (res.success && res.data != null) {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx >= 0) {
        _conversations[idx] = res.data!;
      }
      notifyListeners();
      return true;
    }
    _error = res.error;
    notifyListeners();
    return false;
  }

  Future<bool> addParticipant(String conversationId, String userId) async {
    final res = await _apiService.addGroupParticipant(conversationId, userId);
    if (res.success && res.data != null) {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx >= 0) {
        _conversations[idx] = res.data!;
      }
      notifyListeners();
      return true;
    }
    _error = res.error;
    notifyListeners();
    return false;
  }

  Future<bool> removeParticipant(String conversationId, String userId) async {
    final res = await _apiService.removeGroupParticipant(conversationId, userId);
    if (res.success && res.data != null) {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx >= 0) {
        _conversations[idx] = res.data!;
      }
      notifyListeners();
      return true;
    }
    _error = res.error;
    notifyListeners();
    return false;
  }

  Future<bool> promoteAdmin(String conversationId, String userId) async {
    final res = await _apiService.promoteParticipantToAdmin(conversationId, userId);
    if (res.success && res.data != null) {
      final idx = _conversations.indexWhere((c) => c.id == conversationId);
      if (idx >= 0) {
        _conversations[idx] = res.data!;
      }
      notifyListeners();
      return true;
    }
    _error = res.error;
    notifyListeners();
    return false;
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
