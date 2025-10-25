// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'security_event.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

SecurityEvent _$SecurityEventFromJson(Map<String, dynamic> json) =>
    SecurityEvent(
      id: json['id'] as String,
      userId: json['userId'] as String?,
      type: json['type'] as String,
      meta: json['meta'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$SecurityEventToJson(SecurityEvent instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'type': instance.type,
      'meta': instance.meta,
      'createdAt': instance.createdAt.toIso8601String(),
      'user': instance.user,
    };
