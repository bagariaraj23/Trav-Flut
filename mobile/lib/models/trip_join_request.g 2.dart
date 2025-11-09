// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip_join_request.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

TripJoinRequest _$TripJoinRequestFromJson(Map<String, dynamic> json) =>
    TripJoinRequest(
      id: json['id'] as String,
      tripId: json['tripId'] as String,
      senderId: json['senderId'] as String,
      receiverId: json['receiverId'] as String,
      status: $enumDecode(_$TripJoinRequestStatusEnumMap, json['status']),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      trip: json['trip'] == null
          ? null
          : TripJoinRequestTrip.fromJson(json['trip'] as Map<String, dynamic>),
      sender: json['sender'] == null
          ? null
          : User.fromJson(json['sender'] as Map<String, dynamic>),
      receiver: json['receiver'] == null
          ? null
          : User.fromJson(json['receiver'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TripJoinRequestToJson(TripJoinRequest instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tripId': instance.tripId,
      'senderId': instance.senderId,
      'receiverId': instance.receiverId,
      'status': _$TripJoinRequestStatusEnumMap[instance.status]!,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'trip': instance.trip,
      'sender': instance.sender,
      'receiver': instance.receiver,
    };

const _$TripJoinRequestStatusEnumMap = {
  TripJoinRequestStatus.pending: 'PENDING',
  TripJoinRequestStatus.accepted: 'ACCEPTED',
  TripJoinRequestStatus.rejected: 'REJECTED',
};

TripJoinRequestTrip _$TripJoinRequestTripFromJson(Map<String, dynamic> json) =>
    TripJoinRequestTrip(
      id: json['id'] as String,
      title: json['title'] as String,
      coverMediaUrl: json['coverMediaUrl'] as String?,
      userId: json['userId'] as String,
      destinations: (json['destinations'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      status: json['status'] as String,
      startDate: json['startDate'] == null
          ? null
          : DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
    );

Map<String, dynamic> _$TripJoinRequestTripToJson(
        TripJoinRequestTrip instance) =>
    <String, dynamic>{
      'id': instance.id,
      'title': instance.title,
      'coverMediaUrl': instance.coverMediaUrl,
      'userId': instance.userId,
      'destinations': instance.destinations,
      'status': instance.status,
      'startDate': instance.startDate?.toIso8601String(),
      'endDate': instance.endDate?.toIso8601String(),
    };
