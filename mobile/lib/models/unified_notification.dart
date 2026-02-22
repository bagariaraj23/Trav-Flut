/// Unified notification item: follow request, like, comment, or tag.
/// Matches backend GET /users/me/notifications response shape.
class UnifiedNotificationItem {
  final String type; // 'FOLLOW_REQUEST' | 'LIKE' | 'COMMENT_LIKE' | 'COMMENT' | 'TAG'
  final String id;
  final String createdAt;
  final String? readAt;
  final UnifiedNotificationActor actor;
  final String? followRequestId;
  final String? entityType;
  final String? entityId;
  final String? contentPreview;

  /// For comment-like: post to navigate to
  final String? postEntityType;
  final String? postEntityId;

  /// For scroll-to-comment: comment id to scroll to
  final String? commentId;

  /// For COMMENT_REPLY: parent comment id (for grouping)
  final String? parentCommentId;

  /// For TAG: trip id to navigate to /trip/:tripId/thread
  final String? tripId;

  /// Trip title for copy when notification is about a trip thread entry (e.g. "liked your entry in [tripName]")
  final String? tripName;

  /// Optional thread entry target for in-thread highlight
  final String? threadEntryId;

  const UnifiedNotificationItem({
    required this.type,
    required this.id,
    required this.createdAt,
    this.readAt,
    required this.actor,
    this.followRequestId,
    this.entityType,
    this.entityId,
    this.contentPreview,
    this.postEntityType,
    this.postEntityId,
    this.commentId,
    this.parentCommentId,
    this.tripId,
    this.tripName,
    this.threadEntryId,
  });

  factory UnifiedNotificationItem.fromJson(Map<String, dynamic> json) {
    return UnifiedNotificationItem(
      type: json['type'] as String? ?? 'FOLLOW_REQUEST',
      id: json['id'] as String? ?? '',
      createdAt: json['createdAt'] as String? ?? '',
      readAt: json['readAt'] as String?,
      actor: UnifiedNotificationActor.fromJson(
        (json['actor'] as Map<String, dynamic>?) ?? {},
      ),
      followRequestId: json['followRequestId'] as String?,
      entityType: json['entityType'] as String?,
      entityId: json['entityId'] as String?,
      contentPreview: json['contentPreview'] as String?,
      postEntityType: json['postEntityType'] as String?,
      postEntityId: json['postEntityId'] as String?,
      commentId: json['commentId'] as String?,
      parentCommentId: json['parentCommentId'] as String?,
      tripId: json['tripId'] as String?,
      tripName: json['tripName'] as String?,
      threadEntryId: json['threadEntryId'] as String?,
    );
  }

  /// Creates a copy of this notification with the given fields replaced.
  UnifiedNotificationItem copyWith({
    String? type,
    String? id,
    String? createdAt,
    String? readAt,
    bool clearReadAt = false,
    UnifiedNotificationActor? actor,
    String? followRequestId,
    String? entityType,
    String? entityId,
    String? contentPreview,
    String? postEntityType,
    String? postEntityId,
    String? commentId,
    String? parentCommentId,
    String? tripId,
    String? tripName,
    String? threadEntryId,
  }) {
    return UnifiedNotificationItem(
      type: type ?? this.type,
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      readAt: clearReadAt ? null : (readAt ?? this.readAt),
      actor: actor ?? this.actor,
      followRequestId: followRequestId ?? this.followRequestId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      contentPreview: contentPreview ?? this.contentPreview,
      postEntityType: postEntityType ?? this.postEntityType,
      postEntityId: postEntityId ?? this.postEntityId,
      commentId: commentId ?? this.commentId,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      tripId: tripId ?? this.tripId,
      tripName: tripName ?? this.tripName,
      threadEntryId: threadEntryId ?? this.threadEntryId,
    );
  }

  /// Serializes this notification to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'type': type,
      'id': id,
      'createdAt': createdAt,
      if (readAt != null) 'readAt': readAt,
      'actor': actor.toJson(),
      if (followRequestId != null) 'followRequestId': followRequestId,
      if (entityType != null) 'entityType': entityType,
      if (entityId != null) 'entityId': entityId,
      if (contentPreview != null) 'contentPreview': contentPreview,
      if (postEntityType != null) 'postEntityType': postEntityType,
      if (postEntityId != null) 'postEntityId': postEntityId,
      if (commentId != null) 'commentId': commentId,
      if (parentCommentId != null) 'parentCommentId': parentCommentId,
      if (tripId != null) 'tripId': tripId,
      if (tripName != null) 'tripName': tripName,
      if (threadEntryId != null) 'threadEntryId': threadEntryId,
    };
  }

  bool get isFollowRequest => type == 'FOLLOW_REQUEST';
  bool get isLike => type == 'LIKE' || type == 'COMMENT_LIKE';
  bool get isCommentLike => type == 'COMMENT_LIKE';
  bool get isComment => type == 'COMMENT';
  bool get isCommentReply => type == 'COMMENT_REPLY';
  bool get isTag => type == 'TAG';

  /// For deep link: post entity type to navigate to
  String? get navEntityType => postEntityType ?? entityType;

  /// For deep link: post entity id to navigate to
  String? get navEntityId => postEntityId ?? entityId;

  /// For deep link: comment id to scroll to (for post-comment and comment-like)
  String? get scrollToCommentId =>
      commentId ?? (isCommentLike && entityType == 'COMMENT' ? entityId : null);

  /// For deep link: thread entry id when notification originates from thread entries
  String? get highlightThreadEntryId =>
      threadEntryId ??
      (navEntityType == 'TRIP_THREAD_ENTRY' ? navEntityId : null);

  /// True when this notification is about a trip thread entry (like/comment on entry).
  bool get isTripThreadEntry =>
      entityType == 'TRIP_THREAD_ENTRY' ||
      postEntityType == 'TRIP_THREAD_ENTRY';
}

class UnifiedNotificationActor {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;

  const UnifiedNotificationActor({
    required this.id,
    this.username,
    this.name,
    this.avatarUrl,
  });

  factory UnifiedNotificationActor.fromJson(Map<String, dynamic> json) {
    return UnifiedNotificationActor(
      id: json['id'] as String? ?? '',
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
    );
  }

  /// Serializes this actor to a JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      if (username != null) 'username': username,
      if (name != null) 'name': name,
      if (avatarUrl != null) 'avatarUrl': avatarUrl,
    };
  }

  String get displayName => (name ?? username ?? 'Someone').trim();
}

class NotificationsPayload {
  final List<UnifiedNotificationItem> items;
  final bool hasMore;
  final String? nextCursor;

  const NotificationsPayload({
    required this.items,
    required this.hasMore,
    this.nextCursor,
  });
}
