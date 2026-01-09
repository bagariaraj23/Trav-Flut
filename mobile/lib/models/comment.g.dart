// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comment.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Comment _$CommentFromJson(Map<String, dynamic> json) => Comment(
  id: json['id'] as String,
  userId: json['userId'] as String,
  entityType: json['entityType'] as String,
  entityId: json['entityId'] as String,
  contentText: json['contentText'] as String,
  parentCommentId: json['parentCommentId'] as String?,
  createdAt: DateTime.parse(json['createdAt'] as String),
  updatedAt: DateTime.parse(json['updatedAt'] as String),
  user: json['user'] == null
      ? null
      : User.fromJson(json['user'] as Map<String, dynamic>),
  replyCount: (json['replyCount'] as num?)?.toInt(),
);

Map<String, dynamic> _$CommentToJson(Comment instance) => <String, dynamic>{
  'id': instance.id,
  'userId': instance.userId,
  'entityType': instance.entityType,
  'entityId': instance.entityId,
  'contentText': instance.contentText,
  'parentCommentId': instance.parentCommentId,
  'createdAt': instance.createdAt.toIso8601String(),
  'updatedAt': instance.updatedAt.toIso8601String(),
  'user': instance.user,
  'replyCount': instance.replyCount,
};
