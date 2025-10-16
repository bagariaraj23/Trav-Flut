import 'package:json_annotation/json_annotation.dart';
import 'package:tripthread/models/user.dart';

part 'trip_join_request.g.dart';

enum TripJoinRequestStatus {
  @JsonValue('PENDING')
  pending,
  @JsonValue('ACCEPTED')
  accepted,
  @JsonValue('REJECTED')
  rejected,
}

@JsonSerializable()
class TripJoinRequest {
  final String id;
  final String tripId;
  final String senderId;
  final String receiverId;
  final TripJoinRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final TripJoinRequestTrip? trip;
  final User? sender;
  final User? receiver;

  const TripJoinRequest({
    required this.id,
    required this.tripId,
    required this.senderId,
    required this.receiverId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.trip,
    this.sender,
    this.receiver,
  });

  factory TripJoinRequest.fromJson(Map<String, dynamic> json) =>
      _$TripJoinRequestFromJson(json);
  Map<String, dynamic> toJson() => _$TripJoinRequestToJson(this);
}

@JsonSerializable()
class TripJoinRequestTrip {
  final String id;
  final String title;
  final String? coverMediaUrl;
  final String userId;
  final List<String> destinations;
  final String status;
  final DateTime? startDate;
  final DateTime? endDate;

  const TripJoinRequestTrip({
    required this.id,
    required this.title,
    this.coverMediaUrl,
    required this.userId,
    required this.destinations,
    required this.status,
    this.startDate,
    this.endDate,
  });

  factory TripJoinRequestTrip.fromJson(Map<String, dynamic> json) =>
      _$TripJoinRequestTripFromJson(json);
  Map<String, dynamic> toJson() => _$TripJoinRequestTripToJson(this);
}
