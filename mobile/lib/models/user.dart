import 'package:json_annotation/json_annotation.dart';

part 'user.g.dart';

@JsonSerializable()
class User {
  final String id;
  final String email;
  final String? username;
  final String? name;
  final String? avatarUrl;
  final String? bio;
  final bool isPrivate;
  final DateTime createdAt;
  final DateTime updatedAt;

  const User({
    required this.id,
    required this.email,
    this.username,
    this.name,
    this.avatarUrl,
    this.bio,
    required this.isPrivate,
    required this.createdAt,
    required this.updatedAt,
  });

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
  Map<String, dynamic> toJson() => _$UserToJson(this);

  User copyWith({
    String? id,
    String? email,
    String? username,
    String? name,
    String? avatarUrl,
    String? bio,
    bool? isPrivate,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      username: username ?? this.username,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      isPrivate: isPrivate ?? this.isPrivate,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@JsonSerializable()
class UserStats {
  final int tripCount;
  final int followerCount;
  final int followingCount;

  const UserStats({
    required this.tripCount,
    required this.followerCount,
    required this.followingCount,
  });

  factory UserStats.fromJson(Map<String, dynamic> json) => _$UserStatsFromJson(json);
  Map<String, dynamic> toJson() => _$UserStatsToJson(this);
}

@JsonSerializable()
class AuthResponse {
  final User user;
  final String accessToken;
  final String refreshToken;

  const AuthResponse({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResponse.fromJson(Map<String, dynamic> json) => _$AuthResponseFromJson(json);
  Map<String, dynamic> toJson() => _$AuthResponseToJson(this);
}

@JsonSerializable()
class DiscoverUser {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;
  final String? bio;
  final bool isPrivate;
  final bool isFollowing;
  final bool isFollowedBy;
  final String? followRequestStatus; // "PENDING", "ACCEPTED", "REJECTED", or null
  final bool? hasRequestedToFollow;
  final bool? hasPendingRequestFrom;

  const DiscoverUser({
    required this.id,
    this.username,
    this.name,
    this.avatarUrl,
    this.bio,
    required this.isPrivate,
    required this.isFollowing,
    required this.isFollowedBy,
    this.followRequestStatus,
    this.hasRequestedToFollow,
    this.hasPendingRequestFrom,
  });

  factory DiscoverUser.fromJson(Map<String, dynamic> json) => _$DiscoverUserFromJson(json);
  Map<String, dynamic> toJson() => _$DiscoverUserToJson(this);

  DiscoverUser copyWith({
    String? id,
    String? username,
    String? name,
    String? avatarUrl,
    String? bio,
    bool? isPrivate,
    bool? isFollowing,
    bool? isFollowedBy,
    String? followRequestStatus,
    bool? hasRequestedToFollow,
    bool? hasPendingRequestFrom,
  }) {
    return DiscoverUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      bio: bio ?? this.bio,
      isPrivate: isPrivate ?? this.isPrivate,
      isFollowing: isFollowing ?? this.isFollowing,
      isFollowedBy: isFollowedBy ?? this.isFollowedBy,
      followRequestStatus: followRequestStatus ?? this.followRequestStatus,
      hasRequestedToFollow: hasRequestedToFollow ?? this.hasRequestedToFollow,
      hasPendingRequestFrom: hasPendingRequestFrom ?? this.hasPendingRequestFrom,
    );
  }
}

@JsonSerializable()
class FollowRequest {
  final String id;
  final String senderId;
  final String receiverId;
  final String status; // "PENDING", "ACCEPTED", "REJECTED"
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? sender;
  final User? receiver;

  const FollowRequest({
    required this.id,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.sender,
    this.receiver,
  });

  factory FollowRequest.fromJson(Map<String, dynamic> json) => _$FollowRequestFromJson(json);
  Map<String, dynamic> toJson() => _$FollowRequestToJson(this);
}