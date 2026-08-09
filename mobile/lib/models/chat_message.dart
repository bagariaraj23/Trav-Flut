class ChatMessageModel {
  final String id;
  final String conversationId;
  final String senderId;
  final String content;
  final String? replyToMessageId;
  final String? deletedAt;
  final String createdAt;
  final String updatedAt;
  final ChatMessageSender sender;
  final List<ChatMessageAttachment> attachments;
  final ChatMessagePreview? replyTo;

  /// Client-only: true while the REST call is in-flight (optimistic insert).
  final bool isPending;

  /// Client-only: true when the REST call failed; allows tap-to-retry.
  final bool isFailed;

  /// Client-only: temp ID generated before the server assigns a real one.
  /// Used to replace the pending bubble with the confirmed message.
  final String? pendingId;

  const ChatMessageModel({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.content,
    this.replyToMessageId,
    this.deletedAt,
    required this.createdAt,
    required this.updatedAt,
    required this.sender,
    required this.attachments,
    this.replyTo,
    this.isPending = false,
    this.isFailed = false,
    this.pendingId,
  });

  /// Creates a placeholder message shown immediately while the send is in-flight.
  /// [replyTo] is optional — omitting it just means the reply preview won't
  /// be visible on the optimistic bubble, which is fine since it will be
  /// replaced by the confirmed message from the server shortly.
  factory ChatMessageModel.optimistic({
    required String pendingId,
    required String conversationId,
    required String senderId,
    required String content,
    required ChatMessageSender sender,
    String? replyToMessageId,
  }) {
    final now = DateTime.now().toUtc().toIso8601String();
    return ChatMessageModel(
      id: pendingId,
      conversationId: conversationId,
      senderId: senderId,
      content: content,
      replyToMessageId: replyToMessageId,
      deletedAt: null,
      createdAt: now,
      updatedAt: now,
      sender: sender,
      attachments: const [],
      replyTo: null,
      isPending: true,
      isFailed: false,
      pendingId: pendingId,
    );
  }

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    final senderId = (json['senderId'] as String?) ?? '';
    final senderJson = json['sender'] as Map<String, dynamic>?;
    return ChatMessageModel(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: senderId,
      content: (json['content'] as String?) ?? '',
      replyToMessageId: json['replyToMessageId'] as String?,
      deletedAt: json['deletedAt'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      sender: senderJson != null
          ? ChatMessageSender.fromJson(senderJson)
          : ChatMessageSender(id: senderId),
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((e) => ChatMessageAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      replyTo: json['replyTo'] != null
          ? ChatMessagePreview.fromJson(json['replyTo'] as Map<String, dynamic>)
          : null,
    );
  }

  ChatMessageModel copyWith({
    String? id,
    String? content,
    String? deletedAt,
    List<ChatMessageAttachment>? attachments,
    ChatMessagePreview? replyTo,
    bool? isPending,
    bool? isFailed,
  }) {
    return ChatMessageModel(
      id: id ?? this.id,
      conversationId: conversationId,
      senderId: senderId,
      content: content ?? this.content,
      replyToMessageId: replyToMessageId,
      deletedAt: deletedAt ?? this.deletedAt,
      createdAt: createdAt,
      updatedAt: updatedAt,
      sender: sender,
      attachments: attachments ?? this.attachments,
      replyTo: replyTo ?? this.replyTo,
      isPending: isPending ?? this.isPending,
      isFailed: isFailed ?? this.isFailed,
      pendingId: pendingId,
    );
  }
}

class ChatMessageSender {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;

  const ChatMessageSender({
    required this.id,
    this.username,
    this.name,
    this.avatarUrl,
  });

  factory ChatMessageSender.fromJson(Map<String, dynamic> json) {
    return ChatMessageSender(
      id: json['id'] as String,
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }
}

class ChatMessageAttachment {
  final String id;
  final String url;
  final String type;
  final String publicId;
  final int? width;
  final int? height;
  final double? duration;

  const ChatMessageAttachment({
    required this.id,
    required this.url,
    required this.type,
    required this.publicId,
    this.width,
    this.height,
    this.duration,
  });

  factory ChatMessageAttachment.fromJson(Map<String, dynamic> json) {
    return ChatMessageAttachment(
      id: json['id'] as String,
      url: json['url'] as String,
      type: json['type'] as String,
      publicId: json['publicId'] as String,
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toDouble(),
    );
  }
}

class ChatMessagePreview {
  final String id;
  final String content;
  final String senderId;
  final String createdAt;

  const ChatMessagePreview({
    required this.id,
    required this.content,
    required this.senderId,
    required this.createdAt,
  });

  factory ChatMessagePreview.fromJson(Map<String, dynamic> json) {
    return ChatMessagePreview(
      id: json['id'] as String,
      content: json['content'] as String,
      senderId: json['senderId'] as String,
      createdAt: json['createdAt'] as String,
    );
  }
}

class PaginatedChatMessages {
  final List<ChatMessageModel> messages;
  final String? nextCursor;
  final bool hasMore;

  const PaginatedChatMessages({
    required this.messages,
    this.nextCursor,
    required this.hasMore,
  });

  factory PaginatedChatMessages.fromJson(Map<String, dynamic> json) {
    return PaginatedChatMessages(
      messages: (json['messages'] as List<dynamic>?)
              ?.map((e) => ChatMessageModel.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] as bool? ?? false,
    );
  }
}
