// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'comment_user.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CommentUser _$CommentUserFromJson(Map<String, dynamic> json) => CommentUser(
  id: json['id'] as String,
  username: json['username'] as String?,
  name: json['name'] as String?,
  avatarUrl: json['avatarUrl'] as String?,
);

Map<String, dynamic> _$CommentUserToJson(CommentUser instance) =>
    <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'name': instance.name,
      'avatarUrl': instance.avatarUrl,
    };
