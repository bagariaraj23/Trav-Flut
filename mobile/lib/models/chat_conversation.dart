class ChatConversationSummary {
  final String id;
  final String type; // DM, GROUP, TRIP
  final String? tripId;
  final String? name;
  final String? avatarUrl;
  final List<ChatParticipant> participants;
  final ChatMessagePreview? lastMessage;
  final int unreadCount;
  final String? lastReadAt;
  final String createdAt;
  final String updatedAt;

  const ChatConversationSummary({
    required this.id,
    required this.type,
    this.tripId,
    this.name,
    this.avatarUrl,
    required this.participants,
    this.lastMessage,
    required this.unreadCount,
    this.lastReadAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ChatConversationSummary.fromJson(Map<String, dynamic> json) {
    return ChatConversationSummary(
      id: json['id'] as String,
      type: json['type'] as String,
      tripId: json['tripId'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      participants: (json['participants'] as List<dynamic>?)
              ?.map((e) => ChatParticipant.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      lastMessage: json['lastMessage'] != null
          ? ChatMessagePreview.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      unreadCount: (json['unreadCount'] as num?)?.toInt() ?? 0,
      lastReadAt: json['lastReadAt'] as String?,
      createdAt: json['createdAt'] as String,
      updatedAt: json['updatedAt'] as String,
    );
  }

  ChatConversationSummary copyWith({
    String? id,
    String? type,
    String? tripId,
    String? name,
    String? avatarUrl,
    List<ChatParticipant>? participants,
    ChatMessagePreview? lastMessage,
    int? unreadCount,
    String? lastReadAt,
    String? createdAt,
    String? updatedAt,
    bool clearAvatar = false,
    bool clearLastMessage = false,
  }) {
    return ChatConversationSummary(
      id: id ?? this.id,
      type: type ?? this.type,
      tripId: tripId ?? this.tripId,
      name: name ?? this.name,
      avatarUrl: clearAvatar ? null : (avatarUrl ?? this.avatarUrl),
      participants: participants ?? this.participants,
      lastMessage: clearLastMessage ? null : (lastMessage ?? this.lastMessage),
      unreadCount: unreadCount ?? this.unreadCount,
      lastReadAt: lastReadAt ?? this.lastReadAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

class ChatParticipant {
  final String id;
  final String userId;
  final String? username;
  final String? name;
  final String? avatarUrl;
  final String role;
  final String? lastReadAt;

  const ChatParticipant({
    required this.id,
    required this.userId,
    this.username,
    this.name,
    this.avatarUrl,
    required this.role,
    this.lastReadAt,
  });

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id'] as String,
      userId: json['userId'] as String,
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      role: json['role'] as String? ?? 'MEMBER',
      lastReadAt: json['lastReadAt'] as String?,
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
