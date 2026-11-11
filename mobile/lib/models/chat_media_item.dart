class ChatMediaItem {
  final String id;
  final String url;
  final String type;
  final String messageId;
  final DateTime createdAt;

  const ChatMediaItem({
    required this.id,
    required this.url,
    required this.type,
    required this.messageId,
    required this.createdAt,
  });

  bool get isVideo => type == 'VIDEO';

  factory ChatMediaItem.fromJson(Map<String, dynamic> json) {
    return ChatMediaItem(
      id: json['id'] as String,
      url: json['url'] as String? ?? '',
      type: json['type'] as String? ?? 'IMAGE',
      messageId: json['messageId'] as String? ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }
}

class ChatMediaPage {
  final List<ChatMediaItem> items;
  final String? nextCursor;
  final bool hasMore;

  const ChatMediaPage({
    required this.items,
    required this.nextCursor,
    required this.hasMore,
  });

  factory ChatMediaPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'] as List<dynamic>? ?? [];
    return ChatMediaPage(
      items: raw
          .map((item) => ChatMediaItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] == true,
    );
  }
}

class SafetyPerson {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;
  final String action;

  const SafetyPerson({
    required this.id,
    required this.username,
    required this.name,
    required this.avatarUrl,
    required this.action,
  });

  String get label {
    final display = name?.trim();
    if (display != null && display.isNotEmpty) return display;
    final handle = username?.trim();
    if (handle != null && handle.isNotEmpty) return handle;
    return 'Traveler';
  }

  factory SafetyPerson.fromJson(Map<String, dynamic> json) {
    return SafetyPerson(
      id: json['id'] as String,
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      action: json['action'] as String? ?? '',
    );
  }
}

class SafetyPeoplePage {
  final List<SafetyPerson> people;
  final String? nextCursor;
  final bool hasMore;

  const SafetyPeoplePage({
    required this.people,
    required this.nextCursor,
    required this.hasMore,
  });

  factory SafetyPeoplePage.fromJson(Map<String, dynamic> json) {
    final raw = json['people'] as List<dynamic>? ?? [];
    return SafetyPeoplePage(
      people: raw
          .map((item) => SafetyPerson.fromJson(item as Map<String, dynamic>))
          .toList(),
      nextCursor: json['nextCursor'] as String?,
      hasMore: json['hasMore'] == true,
    );
  }
}
