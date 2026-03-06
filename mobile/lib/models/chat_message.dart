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
  });

  factory ChatMessageModel.fromJson(Map<String, dynamic> json) {
    return ChatMessageModel(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      content: json['content'] as String,
      replyToMessageId: json['replyToMessageId'] as String?,
      deletedAt: json['deletedAt'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
      sender: ChatMessageSender.fromJson(json['sender'] as Map<String, dynamic>),
      attachments: (json['attachments'] as List<dynamic>?)
              ?.map((e) => ChatMessageAttachment.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      replyTo: json['replyTo'] != null
          ? ChatMessagePreview.fromJson(json['replyTo'] as Map<String, dynamic>)
          : null,
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
