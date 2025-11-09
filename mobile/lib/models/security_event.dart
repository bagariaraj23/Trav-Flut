import 'package:json_annotation/json_annotation.dart';
import 'package:tripthread/models/user.dart';

part 'security_event.g.dart';

@JsonSerializable()
class SecurityEvent {
  final String id;
  final String? userId;
  final String type;
  final Map<String, dynamic>? meta;
  final DateTime createdAt;
  final User? user;

  const SecurityEvent({
    required this.id,
    this.userId,
    required this.type,
    this.meta,
    required this.createdAt,
    this.user,
  });

  factory SecurityEvent.fromJson(Map<String, dynamic> json) =>
      _$SecurityEventFromJson(json);

  Map<String, dynamic> toJson() => _$SecurityEventToJson(this);
}
