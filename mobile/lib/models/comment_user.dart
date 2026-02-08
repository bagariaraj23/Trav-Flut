import 'package:json_annotation/json_annotation.dart';

part 'comment_user.g.dart';

/// Lightweight user model for comment contexts
/// Matches backend USER_PUBLIC_SELECT and USER_MINIMAL_SELECT
/// This prevents the need to patch missing user fields on the mobile side
@JsonSerializable()
class CommentUser {
  final String id;
  final String? username;
  final String? name;
  final String? avatarUrl;

  const CommentUser({
    required this.id,
    this.username,
    this.name,
    this.avatarUrl,
  });

  factory CommentUser.fromJson(Map<String, dynamic> json) =>
      _$CommentUserFromJson(json);

  Map<String, dynamic> toJson() => _$CommentUserToJson(this);

  CommentUser copyWith({
    String? id,
    String? username,
    String? name,
    String? avatarUrl,
  }) {
    return CommentUser(
      id: id ?? this.id,
      username: username ?? this.username,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }

  /// Display name: prioritizes name, falls back to username, then id
  String get displayName => name ?? username ?? 'User $id';

  /// Username with @ prefix, or fallback to id
  String get handle =>
      username != null ? '@$username' : '@${id.substring(0, 8)}';
}
