import 'package:json_annotation/json_annotation.dart';

part 'follow_status.g.dart';

@JsonSerializable()
class FollowStatusResponse {
  final bool isFollowing;
  final bool isFollowedBy;
  final bool isRequestPending;
  final bool isPrivate;

  const FollowStatusResponse({
    required this.isFollowing,
    required this.isFollowedBy,
    required this.isRequestPending,
    required this.isPrivate,
  });

  factory FollowStatusResponse.fromJson(Map<String, dynamic> json) => _$FollowStatusResponseFromJson(json);
  Map<String, dynamic> toJson() => _$FollowStatusResponseToJson(this);
}

@JsonSerializable()
class FollowRequestDto {
  final String id;
  final String followerId;
  final String followeeId;
  final String status;
  final DateTime createdAt;
  final UserFollowDto follower;

  const FollowRequestDto({
    required this.id,
    required this.followerId,
    required this.followeeId,
    required this.status,
    required this.createdAt,
    required this.follower,
  });

  factory FollowRequestDto.fromJson(Map<String, dynamic> json) => _$FollowRequestDtoFromJson(json);
  Map<String, dynamic> toJson() => _$FollowRequestDtoToJson(this);
}

@JsonSerializable()
class UserFollowDto {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;
  final String? bio;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserFollowDto({
    required this.id,
    this.username,
    this.name,
    this.avatarUrl,
    this.bio,
    required this.isPrivate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserFollowDto.fromJson(Map<String, dynamic> json) => _$UserFollowDtoFromJson(json);
  Map<String, dynamic> toJson() => _$UserFollowDtoToJson(this);
}
