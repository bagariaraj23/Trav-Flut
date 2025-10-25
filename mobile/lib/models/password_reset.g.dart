// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'password_reset.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PasswordReset _$PasswordResetFromJson(Map<String, dynamic> json) =>
    PasswordReset(
      id: json['id'] as String,
      userId: json['userId'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String),
      usedAt: json['usedAt'] == null
          ? null
          : DateTime.parse(json['usedAt'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      createdIp: json['createdIp'] as String?,
      userAgent: json['userAgent'] as String?,
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PasswordResetToJson(PasswordReset instance) =>
    <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'expiresAt': instance.expiresAt.toIso8601String(),
      'usedAt': instance.usedAt?.toIso8601String(),
      'createdAt': instance.createdAt.toIso8601String(),
      'createdIp': instance.createdIp,
      'userAgent': instance.userAgent,
      'user': instance.user,
    };
