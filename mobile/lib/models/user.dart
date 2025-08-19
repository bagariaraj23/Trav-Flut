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

  factory DiscoverUser.fromJson(Map<String, dynamic> json) {
    return DiscoverUser(
      id: json['id'] as String,
      username: json['username'] as String?,
      name: json['name'] as String?,
      avatarUrl: json['avatarUrl'] as String?,
      bio: json['bio'] as String?,
      isPrivate: json['isPrivate'] as bool,
      isFollowing: json['isFollowing'] as bool,
      isFollowedBy: json['isFollowedBy'] as bool,
      followRequestStatus: json['followRequestStatus'] as String?,
      hasRequestedToFollow: json['hasRequestedToFollow'] as bool?,
      hasPendingRequestFrom: json['hasPendingRequestFrom'] as bool?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'username': username,
      'name': name,
      'avatarUrl': avatarUrl,
      'bio': bio,
      'isPrivate': isPrivate,
      'isFollowing': isFollowing,
      'isFollowedBy': isFollowedBy,
      'followRequestStatus': followRequestStatus,
      'hasRequestedToFollow': hasRequestedToFollow,
      'hasPendingRequestFrom': hasPendingRequestFrom,
    };
  }

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

  factory FollowRequest.fromJson(Map<String, dynamic> json) {
    return FollowRequest(
      id: json['id'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      sender: json['sender'] != null ? User.fromJson(json['sender'] as Map<String, dynamic>) : null,
      receiver: json['receiver'] != null ? User.fromJson(json['receiver'] as Map<String, dynamic>) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'senderId': senderId,
      'receiverId': receiverId,
      'status': status,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'sender': sender?.toJson(),
      'receiver': receiver?.toJson(),
    };
  }
}