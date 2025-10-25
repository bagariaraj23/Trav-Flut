import 'package:json_annotation/json_annotation.dart';
import 'package:tripthread/models/user.dart';

part 'password_reset.g.dart';

@JsonSerializable()
class PasswordReset {
  final String id;
  final String userId;
  final DateTime expiresAt;
  final DateTime? usedAt;
  final DateTime createdAt;
  final String? createdIp;
  final String? userAgent;
  final User? user;

  const PasswordReset({
    required this.id,
    required this.userId,
    required this.expiresAt,
    this.usedAt,
    required this.createdAt,
    this.createdIp,
    this.userAgent,
    this.user,
  });

  factory PasswordReset.fromJson(Map<String, dynamic> json) =>
      _$PasswordResetFromJson(json);

  Map<String, dynamic> toJson() => _$PasswordResetToJson(this);
}
