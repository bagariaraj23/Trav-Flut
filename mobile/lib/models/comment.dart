import 'package:json_annotation/json_annotation.dart';
import 'package:tripthread/models/user.dart';

part 'comment.g.dart';

@JsonSerializable()
class Comment {
  final String id;
  final String userId;
  final String entityType;
  final String entityId;
  final String contentText;
  final String? parentCommentId;
  final int likeCount;
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? user;
  final int? replyCount;

  const Comment({
    required this.id,
    required this.userId,
    required this.entityType,
    required this.entityId,
    required this.contentText,
    this.parentCommentId,
    this.likeCount = 0,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.replyCount,
  });

  factory Comment.fromJson(Map<String, dynamic> json) =>
      _$CommentFromJson(json);

  Map<String, dynamic> toJson() => _$CommentToJson(this);

  Comment copyWith({
    String? id,
    String? userId,
    String? entityType,
    String? entityId,
    String? contentText,
    String? parentCommentId,
    int? likeCount,
    DateTime? createdAt,
    DateTime? updatedAt,
    User? user,
    int? replyCount,
  }) {
    return Comment(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      entityType: entityType ?? this.entityType,
      entityId: entityId ?? this.entityId,
      contentText: contentText ?? this.contentText,
      parentCommentId: parentCommentId ?? this.parentCommentId,
      likeCount: likeCount ?? this.likeCount,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      user: user ?? this.user,
      replyCount: replyCount ?? this.replyCount,
    );
  }
}
