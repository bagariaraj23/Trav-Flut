/// Unified notification item: follow request, like, comment, or tag.
/// Matches backend GET /users/me/notifications response shape.
class UnifiedNotificationItem {
  final String type; // 'FOLLOW_REQUEST' | 'LIKE' | 'COMMENT' | 'TAG'
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
      threadEntryId: json['threadEntryId'] as String?,
    );
  }

  bool get isFollowRequest => type == 'FOLLOW_REQUEST';
  bool get isLike => type == 'LIKE';
  bool get isComment => type == 'COMMENT';
  bool get isCommentReply => type == 'COMMENT_REPLY';
  bool get isTag => type == 'TAG';

  /// For deep link: post entity type to navigate to
  String? get navEntityType => postEntityType ?? entityType;

  /// For deep link: post entity id to navigate to
  String? get navEntityId => postEntityId ?? entityId;

  /// For deep link: comment id to scroll to (for post-comment and comment-like)
  String? get scrollToCommentId =>
      commentId ?? (isLike && entityType == 'COMMENT' ? entityId : null);

  /// For deep link: thread entry id when notification originates from thread entries
  String? get highlightThreadEntryId =>
      threadEntryId ??
      (navEntityType == 'TRIP_THREAD_ENTRY' ? navEntityId : null);
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

  String get displayName => (name ?? username ?? 'Someone').trim();
}

class NotificationsPayload {
  final List<UnifiedNotificationItem> items;
  final bool hasMore;

  const NotificationsPayload({required this.items, required this.hasMore});
}
