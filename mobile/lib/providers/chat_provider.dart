import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:tripthread/models/chat_conversation.dart';
import 'package:tripthread/models/chat_message.dart' hide ChatMessagePreview;
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

  String? _currentUserId;

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
    _storageService.getUserId().then((id) => _currentUserId = id);
    _socketService.resetConnection();
    _socketService.connect();
  }

  /// Call when the user logs out. Closes WebSocket; [connect] will work again after next sign-in.
  void onAuthSignedOut() {
    _currentUserId = null;
    _socketService.resetConnection();
  }

  void disconnectSocket() {
    // Intentionally left as a no-op so chat stays real-time while app is running.
  }

  void _onMessageNew(String conversationId, ChatMessageModel message) {
    final list = _messagesByConversation[conversationId] ?? [];
    final existingIndex = list.indexWhere((m) => m.id == message.id);
    if (existingIndex >= 0) {
      final updated = [...list];
      updated[existingIndex] = message;
      _messagesByConversation[conversationId] = updated;
    } else {
      _messagesByConversation[conversationId] = [message, ...list];
      if (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android) {
        HapticFeedback.lightImpact();
      }
    }
    _refreshConversationOnMessage(conversationId, message);
    notifyListeners();
  }

  void _refreshConversationOnMessage(String conversationId, ChatMessageModel message) {
    final idx = _conversations.indexWhere((c) => c.id == conversationId);
    if (idx < 0) return;

    final current = _conversations[idx];
    final isFromSelf = _currentUserId != null && message.senderId == _currentUserId;
    final preview = ChatMessagePreview(
      id: message.id,
      content: message.content,
      senderId: message.senderId,
      createdAt: message.createdAt,
    );
    final updated = current.copyWith(
      lastMessage: preview,
      updatedAt: message.updatedAt,
      unreadCount: isFromSelf ? current.unreadCount : current.unreadCount + 1,
    );
    _conversations.removeAt(idx);
    _conversations.insert(0, updated);
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

  /// Returns conversations scoped to a specific trip (filters from the full in-memory list).
  List<ChatConversationSummary> getConversationsForTrip(String tripId) {
    return _conversations.where((c) => c.tripId == tripId).toList();
  }

  Future<void> loadConversations({String? tripId}) async {
    _loadingConversations = true;
    _error = null;
    notifyListeners();

    if (tripId != null) {
      // Only create if we don't already have a TRIP conversation for this trip in memory.
      final alreadyExists = _conversations.any(
        (c) => c.type == 'TRIP' && c.tripId == tripId,
      );
      if (!alreadyExists) {
        // Ignore errors here — if creation fails (e.g. not a participant) the
        // subsequent fetch will return an empty list and surface the right state.
        await createConversation(
          type: 'TRIP',
          participantIds: const [],
          tripId: tripId,
        );
      }
    }

    final res = await _apiService.getChatConversations(tripId: tripId);
    _loadingConversations = false;
    if (res.success && res.data != null) {
      if (tripId != null) {
        // Upsert: merge the trip-filtered results into the full list so that
        // WS events for DMs/other groups still reach their conversations.
        for (final fetched in res.data!) {
          final idx = _conversations.indexWhere((c) => c.id == fetched.id);
          if (idx >= 0) {
            _conversations[idx] = fetched;
          } else {
            _conversations.add(fetched);
          }
        }
      } else {
        // Full refresh from the server — replace the entire list.
        _conversations = res.data!;
      }
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
      _conversations[idx] = _conversations[idx].copyWith(
        unreadCount: 0,
        lastReadAt: DateTime.now().toUtc().toIso8601String(),
      );
      notifyListeners();
    }
  }

  Future<void> ensureConversationLoaded(String conversationId) async {
    if (_conversations.any((c) => c.id == conversationId)) return;
    final res = await _apiService.getChatConversation(conversationId);
    if (res.success && res.data != null) {
      _conversations.insert(0, res.data!);
      notifyListeners();
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
      final conv = res.data!;
      // Upsert: the backend may return an existing conversation (e.g. existing DM or TRIP).
      final idx = _conversations.indexWhere((c) => c.id == conv.id);
      if (idx >= 0) {
        _conversations[idx] = conv;
      } else {
        _conversations.insert(0, conv);
      }
      notifyListeners();
      return conv;
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

  Future<bool> updateGroupInfo(
    String conversationId, {
    String? name,
    String? avatarUrl,
    bool clearAvatar = false,
  }) async {
    final res = await _apiService.updateGroupSettings(
      conversationId,
      name: name,
      avatarUrl: avatarUrl,
      clearAvatar: clearAvatar,
    );
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

  /// Leaves a GROUP conversation. On success, removes all local state for
  /// that conversation so the UI reflects the departure immediately.
  Future<bool> leaveGroup(String conversationId) async {
    final res = await _apiService.leaveGroupConversation(conversationId);
    if (res.success) {
      _conversations.removeWhere((c) => c.id == conversationId);
      _messagesByConversation.remove(conversationId);
      _nextCursorByConversation.remove(conversationId);
      _hasMoreByConversation.remove(conversationId);
      _loadingMessages.remove(conversationId);
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
