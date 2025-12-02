// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'follow_status.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

FollowStatusResponse _$FollowStatusResponseFromJson(
  Map<String, dynamic> json,
) => FollowStatusResponse(
  isFollowing: json['isFollowing'] as bool,
  isFollowedBy: json['isFollowedBy'] as bool,
  isRequestPending: json['isRequestPending'] as bool,
  isPrivate: json['isPrivate'] as bool,
);

Map<String, dynamic> _$FollowStatusResponseToJson(
  FollowStatusResponse instance,
) => <String, dynamic>{
  'isFollowing': instance.isFollowing,
  'isFollowedBy': instance.isFollowedBy,
  'isRequestPending': instance.isRequestPending,
  'isPrivate': instance.isPrivate,
};

FollowRequestDto _$FollowRequestDtoFromJson(Map<String, dynamic> json) =>
    FollowRequestDto(
      id: json['id'] as String,
      followerId: json['followerId'] as String,
      followeeId: json['followeeId'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      follower: UserFollowDto.fromJson(
        json['follower'] as Map<String, dynamic>,
      ),
    );

Map<String, dynamic> _$FollowRequestDtoToJson(FollowRequestDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'followerId': instance.followerId,
      'followeeId': instance.followeeId,
      'status': instance.status,
      'createdAt': instance.createdAt.toIso8601String(),
      'follower': instance.follower,
    };

UserFollowDto _$UserFollowDtoFromJson(Map<String, dynamic> json) =>
    UserFollowDto(
      id: json['id'] as String,
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      isPrivate: json['isPrivate'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$UserFollowDtoToJson(UserFollowDto instance) =>
    <String, dynamic>{
      'id': instance.id,
      'username': instance.username,
      'name': instance.name,
      'avatarUrl': instance.avatarUrl,
      'bio': instance.bio,
      'isPrivate': instance.isPrivate,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };
