import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/models/api_response.dart';
import 'package:tripthread/models/chat_conversation.dart';
import 'package:tripthread/models/chat_message.dart' hide ChatMessagePreview;
import 'package:tripthread/providers/chat_provider.dart';
import 'package:tripthread/services/api_service.dart';
import 'package:tripthread/services/storage_service.dart';

ChatConversationSummary sampleConversation({
  String id = 'conv-1',
  int unreadCount = 0,
  ChatMessagePreview? lastMessage,
}) {
  return ChatConversationSummary(
    id: id,
    type: 'DM',
    participants: const [
      ChatParticipant(
        id: 'part-1',
        userId: 'user-self',
        username: 'self',
        name: 'Self User',
        role: 'MEMBER',
      ),
      ChatParticipant(
        id: 'part-2',
        userId: 'user-other',
        username: 'other',
        name: 'Other User',
        role: 'MEMBER',
      ),
    ],
    unreadCount: unreadCount,
    createdAt: '2026-06-13T10:00:00.000Z',
    updatedAt: '2026-06-13T10:00:00.000Z',
    lastMessage: lastMessage,
  );
}

ChatMessageModel sampleMessage({
  String id = 'msg-1',
  String conversationId = 'conv-1',
  String senderId = 'user-other',
  String content = 'Hello',
}) {
  return ChatMessageModel(
    id: id,
    conversationId: conversationId,
    senderId: senderId,
    content: content,
    createdAt: '2026-06-13T10:01:00.000Z',
    updatedAt: '2026-06-13T10:01:00.000Z',
    sender: ChatMessageSender(
      id: senderId,
      username: senderId == 'user-self' ? 'self' : 'other',
      name: senderId == 'user-self' ? 'Self User' : 'Other User',
    ),
    attachments: const [],
  );
}

class TestStorageService extends StorageService {
  String? userId = 'user-self';

  @override
  Future<String?> getUserId() async => userId;

  @override
  Future<String?> getAccessToken() async => 'test-access-token';
}

class TestChatApiService extends ApiService {
  bool shouldFail = false;
  String? failError;
  List<ChatConversationSummary> conversations = [];
  final Map<String, List<ChatMessageModel>> messagesByConversation = {};
  int markReadCalls = 0;
  bool clearAvatarRequested = false;

  @override
  Future<ApiResponse<List<ChatConversationSummary>>> getChatConversations({
    String? tripId,
  }) async {
    if (shouldFail) {
      return ApiResponse(success: false, error: failError ?? 'Failed to load');
    }
    return ApiResponse(success: true, data: List<ChatConversationSummary>.from(conversations));
  }

  @override
  Future<ApiResponse<ChatConversationSummary>> getChatConversation(String id) async {
    if (shouldFail) {
      return ApiResponse(success: false, error: failError ?? 'Not found');
    }
    final match = conversations.where((c) => c.id == id).toList();
    if (match.isNotEmpty) {
      return ApiResponse(success: true, data: match.first);
    }
    if (id == 'conv-1') {
      return ApiResponse(success: true, data: sampleConversation(id: id));
    }
    return ApiResponse(success: false, error: 'Not found');
  }

  @override
  Future<ApiResponse<PaginatedChatMessages>> getChatMessages(
    String conversationId, {
    int? limit,
    String? before,
  }) async {
    if (shouldFail) {
      return ApiResponse(success: false, error: failError ?? 'Failed to load messages');
    }
    final messages = messagesByConversation[conversationId] ?? [];
    return ApiResponse(
      success: true,
      data: PaginatedChatMessages(
        messages: List<ChatMessageModel>.from(messages),
        nextCursor: null,
        hasMore: false,
      ),
    );
  }

  @override
  Future<ApiResponse<ChatMessageModel>> sendChatMessage(
    String conversationId, {
    required String content,
    String? replyToMessageId,
    List<String>? attachmentMediaIds,
  }) async {
    if (shouldFail) {
      return ApiResponse(success: false, error: failError ?? 'Failed to send');
    }
    return ApiResponse(
      success: true,
      data: sampleMessage(
        id: 'msg-sent',
        conversationId: conversationId,
        senderId: 'user-self',
        content: content,
      ),
    );
  }

  @override
  Future<ApiResponse<void>> markChatConversationRead(String conversationId) async {
    markReadCalls++;
    if (shouldFail) {
      return ApiResponse(success: false, error: failError ?? 'Failed to mark read');
    }
    return const ApiResponse(success: true);
  }

  @override
  Future<ApiResponse<ChatConversationSummary>> createChatConversation({
    required String type,
    required List<String> participantIds,
    String? name,
    String? tripId,
  }) async {
    if (shouldFail) {
      return ApiResponse(success: false, error: failError ?? 'Failed to create');
    }
    return ApiResponse(success: true, data: sampleConversation(id: 'conv-created'));
  }

  @override
  Future<ApiResponse<ChatConversationSummary>> updateGroupSettings(
    String conversationId, {
    String? name,
    String? avatarUrl,
    bool clearAvatar = false,
  }) async {
    if (clearAvatar) clearAvatarRequested = true;
    if (shouldFail) {
      return ApiResponse(success: false, error: failError ?? 'Failed to update');
    }
    return ApiResponse(
      success: true,
      data: sampleConversation(id: conversationId).copyWith(
        name: name,
        avatarUrl: avatarUrl,
        clearAvatar: clearAvatar,
      ),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late TestChatApiService api;
  late TestStorageService storage;
  late ChatProvider provider;

  setUp(() {
    api = TestChatApiService();
    storage = TestStorageService();
    provider = ChatProvider(apiService: api, storageService: storage);
    provider.onAuthSignedIn();
    api.conversations = [
      sampleConversation(unreadCount: 2),
    ];
    api.messagesByConversation['conv-1'] = [
      sampleMessage(),
    ];
  });

  group('ChatProvider', () {
    test('loadConversations populates list', () async {
      expect(provider.conversations, isEmpty);

      await provider.loadConversations();

      expect(provider.conversations, hasLength(1));
      expect(provider.conversations.first.unreadCount, 2);
      expect(provider.loadingConversations, isFalse);
    });

    test('loadMessages caches messages for a conversation', () async {
      final ok = await provider.loadMessages('conv-1');

      expect(ok, isTrue);
      expect(provider.getMessages('conv-1'), hasLength(1));
      expect(provider.getMessages('conv-1').first.content, 'Hello');
    });

    test('sendMessage appends message and updates conversation preview', () async {
      await provider.loadConversations();

      final ok = await provider.sendMessage('conv-1', 'Sent from test');

      expect(ok, isTrue);
      expect(provider.getMessages('conv-1').first.content, 'Sent from test');
      expect(provider.conversations.first.lastMessage?.content, 'Sent from test');
    });

    test('markRead clears unread locally and calls API', () async {
      await provider.loadConversations();
      expect(provider.conversations.first.unreadCount, 2);

      await provider.markRead('conv-1');

      expect(api.markReadCalls, 1);
      expect(provider.conversations.first.unreadCount, 0);
      expect(provider.conversations.first.lastReadAt, isNotNull);
    });

    test('ensureConversationLoaded fetches missing conversation metadata', () async {
      api.conversations = [];

      await provider.ensureConversationLoaded('conv-1');

      expect(provider.conversations, hasLength(1));
      expect(provider.conversations.first.id, 'conv-1');
    });

    test('createConversation inserts new conversation at top', () async {
      await provider.loadConversations();

      final created = await provider.createConversation(
        type: 'DM',
        participantIds: ['user-other'],
      );

      expect(created, isNotNull);
      expect(provider.conversations.first.id, 'conv-created');
    });

    test('updateGroupInfo supports clearAvatar flag', () async {
      await provider.loadConversations();

      final ok = await provider.updateGroupInfo('conv-1', clearAvatar: true);

      expect(ok, isTrue);
      expect(api.clearAvatarRequested, isTrue);
    });

    test('loadConversations surfaces API errors', () async {
      api.shouldFail = true;
      api.failError = 'Network down';

      await provider.loadConversations();

      expect(provider.conversations, isEmpty);
      expect(provider.error, 'Network down');
    });
  });

  group('ChatConversationSummary', () {
    test('copyWith clears avatar when clearAvatar is true', () {
      final original = sampleConversation().copyWith(
        avatarUrl: 'https://example.com/a.png',
      );

      final cleared = original.copyWith(clearAvatar: true);

      expect(cleared.avatarUrl, isNull);
    });
  });
}
