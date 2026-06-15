import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/models/chat_message.dart';

void main() {
  // ChatMessageModel
  group('ChatMessageModel.fromJson', () {
    test('parses full message with sender and attachments', () {
      final json = {
        'id': 'msg-1',
        'conversationId': 'conv-1',
        'senderId': 'user-1',
        'content': 'Hello world',
        'replyToMessageId': null,
        'deletedAt': null,
        'createdAt': '2026-06-13T10:00:00.000Z',
        'updatedAt': '2026-06-13T10:00:00.000Z',
        'sender': {
          'id': 'user-1',
          'username': 'alice',
          'name': 'Alice',
          'avatarUrl': 'https://example.com/avatar.png',
        },
        'attachments': [
          {
            'id': 'att-1',
            'url': 'https://example.com/img.png',
            'type': 'IMAGE',
            'publicId': 'img123',
            'width': 800,
            'height': 600,
          }
        ],
      };

      final msg = ChatMessageModel.fromJson(json);

      expect(msg.id, 'msg-1');
      expect(msg.conversationId, 'conv-1');
      expect(msg.senderId, 'user-1');
      expect(msg.content, 'Hello world');
      expect(msg.deletedAt, isNull);
      expect(msg.sender.username, 'alice');
      expect(msg.attachments, hasLength(1));
      expect(msg.attachments.first.type, 'IMAGE');
      expect(msg.isPending, isFalse);
      expect(msg.isFailed, isFalse);
    });

    test('parses message with replyTo', () {
      final json = {
        'id': 'msg-2',
        'conversationId': 'conv-1',
        'senderId': 'user-2',
        'content': 'Reply here',
        'replyToMessageId': 'msg-1',
        'deletedAt': null,
        'createdAt': '2026-06-13T10:01:00.000Z',
        'updatedAt': '2026-06-13T10:01:00.000Z',
        'sender': {'id': 'user-2', 'username': 'bob'},
        'attachments': [],
        'replyTo': {
          'id': 'msg-1',
          'content': 'Original',
          'senderId': 'user-1',
          'createdAt': '2026-06-13T10:00:00.000Z',
        },
      };

      final msg = ChatMessageModel.fromJson(json);

      expect(msg.replyToMessageId, 'msg-1');
      expect(msg.replyTo, isNotNull);
      expect(msg.replyTo!.content, 'Original');
    });

    test('handles missing optional fields gracefully', () {
      final json = {
        'id': 'min',
        'conversationId': 'c',
        'senderId': 's',
        'content': '',
        'createdAt': '2026-06-13T10:00:00.000Z',
        'updatedAt': '2026-06-13T10:00:00.000Z',
        'sender': {'id': 's', 'username': null},
        'attachments': null,
      };

      final msg = ChatMessageModel.fromJson(json);

      expect(msg.attachments, isEmpty);
      expect(msg.replyTo, isNull);
      expect(msg.replyToMessageId, isNull);
    });

    test('parses deletedAt when present', () {
      final json = {
        'id': 'deleted-msg',
        'conversationId': 'c',
        'senderId': 's',
        'content': '',
        'deletedAt': '2026-06-13T10:05:00.000Z',
        'createdAt': '2026-06-13T10:00:00.000Z',
        'updatedAt': '2026-06-13T10:05:00.000Z',
        'sender': {'id': 's', 'username': 'u'},
        'attachments': [],
      };

      final msg = ChatMessageModel.fromJson(json);

      expect(msg.deletedAt, '2026-06-13T10:05:00.000Z');
    });
  });

  // optimistic factory
  group('ChatMessageModel.optimistic', () {
    late ChatMessageModel pending;

    setUp(() {
      pending = ChatMessageModel.optimistic(
        pendingId: 'pending-id-1',
        conversationId: 'conv-1',
        senderId: 'user-self',
        content: 'Draft message',
        sender: ChatMessageSender(id: 'user-self', username: 'self'),
        replyToMessageId: 'parent-msg',
      );
    });

    test('sets isPending to true', () => expect(pending.isPending, isTrue));
    test('sets isFailed to false', () => expect(pending.isFailed, isFalse));
    test('id equals pendingId', () => expect(pending.id, pending.pendingId));
    test('stores content correctly', () => expect(pending.content, 'Draft message'));
    test('stores replyToMessageId', () => expect(pending.replyToMessageId, 'parent-msg'));
    test('attachments are empty', () => expect(pending.attachments, isEmpty));
    test('replyTo is null (preview not pre-populated)', () => expect(pending.replyTo, isNull));

    test('createdAt is a valid ISO datetime close to now', () {
      final created = DateTime.parse(pending.createdAt);
      final diff = DateTime.now().toUtc().difference(created).abs();
      expect(diff.inSeconds, lessThan(5));
    });
  });

  // copyWith
  group('ChatMessageModel.copyWith', () {
    late ChatMessageModel original;

    setUp(() {
      original = ChatMessageModel.optimistic(
        pendingId: 'p-001',
        conversationId: 'conv-1',
        senderId: 'user-self',
        content: 'Original',
        sender: ChatMessageSender(id: 'user-self', username: 'self'),
      );
    });

    test('marks as failed while preserving pendingId', () {
      final failed = original.copyWith(isPending: false, isFailed: true);
      expect(failed.isFailed, isTrue);
      expect(failed.isPending, isFalse);
      expect(failed.pendingId, 'p-001');
    });

    test('updates id when provided (pending → confirmed)', () {
      final confirmed = original.copyWith(
          id: 'server-id', isPending: false, isFailed: false);
      expect(confirmed.id, 'server-id');
      expect(confirmed.pendingId, 'p-001');
    });

    test('updates content', () {
      const original2 = ChatMessageModel(
        id: 'msg-x',
        conversationId: 'c',
        senderId: 's',
        content: 'Old',
        createdAt: '2026-01-01T00:00:00.000Z',
        updatedAt: '2026-01-01T00:00:00.000Z',
        sender: ChatMessageSender(id: 's', username: 'u'),
        attachments: [],
      );
      final edited = original2.copyWith(content: 'New');
      expect(edited.content, 'New');
      expect(edited.id, 'msg-x');
    });

    test('does not mutate original', () {
      original.copyWith(isFailed: true);
      expect(original.isFailed, isFalse);
    });
  });

  // ChatMessageAttachment
  group('ChatMessageAttachment.fromJson', () {
    test('parses image attachment', () {
      final json = {
        'id': 'att-1',
        'url': 'https://cdn.example.com/img.jpg',
        'type': 'IMAGE',
        'publicId': 'img/123',
        'width': 1920,
        'height': 1080,
        'duration': null,
      };
      final att = ChatMessageAttachment.fromJson(json);
      expect(att.type, 'IMAGE');
      expect(att.width, 1920);
      expect(att.duration, isNull);
    });

    test('parses video attachment with duration', () {
      final json = {
        'id': 'att-2',
        'url': 'https://cdn.example.com/vid.mp4',
        'type': 'VIDEO',
        'publicId': 'vid/456',
        'width': null,
        'height': null,
        'duration': 30.5,
      };
      final att = ChatMessageAttachment.fromJson(json);
      expect(att.type, 'VIDEO');
      expect(att.duration, 30.5);
    });
  });
}
