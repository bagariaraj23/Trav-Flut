// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'trip.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Trip _$TripFromJson(Map<String, dynamic> json) => Trip(
      id: json['id'] as String,
      userId: json['userId'] as String,
      title: json['title'] as String,
      description: json['description'] as String?,
      startDate: DateTime.parse(json['startDate'] as String),
      endDate: DateTime.parse(json['endDate'] as String),
      destinations: (json['destinations'] as List<dynamic>?)
              ?.map((e) => e as String)
              .toList() ??
          [],
      mood: $enumDecodeNullable(_$TripMoodEnumMap, json['mood']),
      type: $enumDecodeNullable(_$TripTypeEnumMap, json['type']),
      coverMediaId: json['coverMediaId'] as String?,
      coverMedia: json['coverMedia'] == null
          ? null
          : Media.fromJson(json['coverMedia'] as Map<String, dynamic>),
      status: $enumDecode(_$TripStatusEnumMap, json['status']),
      entryCount: (json['entryCount'] as num?)?.toInt() ?? 0,
      participantCount: (json['participantCount'] as num?)?.toInt() ?? 1,
      startLocationId: json['startLocationId'] as String?,
      startLocation: json['startLocation'] == null
          ? null
          : Place.fromJson(json['startLocation'] as Map<String, dynamic>),
      endLocationId: json['endLocationId'] as String?,
      endLocation: json['endLocation'] == null
          ? null
          : Place.fromJson(json['endLocation'] as Map<String, dynamic>),
      placeVisits: (json['placeVisits'] as List<dynamic>?)
          ?.map((e) => PlaceOnTrip.fromJson(e as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
      participants: (json['participants'] as List<dynamic>?)
          ?.map((e) => TripParticipant.fromJson(e as Map<String, dynamic>))
          .toList(),
      threadEntries: (json['threadEntries'] as List<dynamic>?)
          ?.map((e) => TripThreadEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
      finalPost: json['finalPost'] == null
          ? null
          : TripFinalPost.fromJson(json['finalPost'] as Map<String, dynamic>),
      counts: json['counts'] == null
          ? null
          : TripCounts.fromJson(json['counts'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TripToJson(Trip instance) => <String, dynamic>{
      'id': instance.id,
      'userId': instance.userId,
      'title': instance.title,
      'description': instance.description,
      'startDate': instance.startDate.toIso8601String(),
      'endDate': instance.endDate.toIso8601String(),
      'destinations': instance.destinations,
      'mood': _$TripMoodEnumMap[instance.mood],
      'type': _$TripTypeEnumMap[instance.type],
      'coverMediaId': instance.coverMediaId,
      'coverMedia': instance.coverMedia,
      'status': _$TripStatusEnumMap[instance.status]!,
      'entryCount': instance.entryCount,
      'participantCount': instance.participantCount,
      'startLocationId': instance.startLocationId,
      'startLocation': instance.startLocation,
      'endLocationId': instance.endLocationId,
      'endLocation': instance.endLocation,
      'placeVisits': instance.placeVisits,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
      'user': instance.user,
      'participants': instance.participants,
      'threadEntries': instance.threadEntries,
      'finalPost': instance.finalPost,
      'counts': instance.counts,
    };

const _$TripMoodEnumMap = {
  TripMood.relaxed: 'RELAXED',
  TripMood.adventure: 'ADVENTURE',
  TripMood.spiritual: 'SPIRITUAL',
  TripMood.cultural: 'CULTURAL',
  TripMood.party: 'PARTY',
  TripMood.mixed: 'MIXED',
};

const _$TripTypeEnumMap = {
  TripType.solo: 'SOLO',
  TripType.group: 'GROUP',
  TripType.couple: 'COUPLE',
  TripType.family: 'FAMILY',
};

const _$TripStatusEnumMap = {
  TripStatus.upcoming: 'UPCOMING',
  TripStatus.ongoing: 'ONGOING',
  TripStatus.ended: 'ENDED',
};

TripCounts _$TripCountsFromJson(Map<String, dynamic> json) => TripCounts(
      threadEntries: (json['threadEntries'] as num).toInt(),
      media: (json['media'] as num).toInt(),
      participants: (json['participants'] as num).toInt(),
    );

Map<String, dynamic> _$TripCountsToJson(TripCounts instance) =>
    <String, dynamic>{
      'threadEntries': instance.threadEntries,
      'media': instance.media,
      'participants': instance.participants,
    };

TripParticipant _$TripParticipantFromJson(Map<String, dynamic> json) =>
    TripParticipant(
      id: json['id'] as String,
      tripId: json['tripId'] as String,
      userId: json['userId'] as String,
      role: json['role'] as String,
      joinedAt: DateTime.parse(json['joinedAt'] as String),
      user: json['user'] == null
          ? null
          : User.fromJson(json['user'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TripParticipantToJson(TripParticipant instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tripId': instance.tripId,
      'userId': instance.userId,
      'role': instance.role,
      'joinedAt': instance.joinedAt.toIso8601String(),
      'user': instance.user,
    };

TripThreadEntry _$TripThreadEntryFromJson(Map<String, dynamic> json) =>
    TripThreadEntry(
      id: json['id'] as String,
      tripId: json['tripId'] as String,
      authorId: json['authorId'] as String,
      type: $enumDecode(_$ThreadEntryTypeEnumMap, json['type']),
      contentText: json['contentText'] as String?,
      mediaId: json['mediaId'] as String?,
      locationName: json['locationName'] as String?,
      gpsCoordinates: json['gpsCoordinates'] == null
          ? null
          : GpsCoordinates.fromJson(
              json['gpsCoordinates'] as Map<String, dynamic>),
      placeId: json['placeId'] as String?,
      place: json['place'] == null
          ? null
          : Place.fromJson(json['place'] as Map<String, dynamic>),
      createdAt: DateTime.parse(json['createdAt'] as String),
      author: User.fromJson(json['author'] as Map<String, dynamic>),
      taggedUsers: (json['taggedUsers'] as List<dynamic>?)
          ?.map((e) => User.fromJson(e as Map<String, dynamic>))
          .toList(),
      media: json['media'] == null
          ? null
          : Media.fromJson(json['media'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TripThreadEntryToJson(TripThreadEntry instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tripId': instance.tripId,
      'authorId': instance.authorId,
      'type': _$ThreadEntryTypeEnumMap[instance.type]!,
      'contentText': instance.contentText,
      'mediaId': instance.mediaId,
      'locationName': instance.locationName,
      'gpsCoordinates': instance.gpsCoordinates,
      'placeId': instance.placeId,
      'place': instance.place,
      'createdAt': instance.createdAt.toIso8601String(),
      'author': instance.author,
      'taggedUsers': instance.taggedUsers,
      'media': instance.media,
    };

const _$ThreadEntryTypeEnumMap = {
  ThreadEntryType.text: 'TEXT',
  ThreadEntryType.media: 'MEDIA',
  ThreadEntryType.location: 'LOCATION',
  ThreadEntryType.checkin: 'CHECKIN',
};

TripFinalPost _$TripFinalPostFromJson(Map<String, dynamic> json) =>
    TripFinalPost(
      id: json['id'] as String,
      tripId: json['tripId'] as String,
      summaryText: json['summaryText'] as String,
      curatedMedia: (json['curatedMedia'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      caption: json['caption'] as String?,
      isPublished: json['isPublished'] as bool,
      createdAt: DateTime.parse(json['createdAt'] as String),
      trip: json['trip'] == null
          ? null
          : Trip.fromJson(json['trip'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$TripFinalPostToJson(TripFinalPost instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tripId': instance.tripId,
      'summaryText': instance.summaryText,
      'curatedMedia': instance.curatedMedia,
      'caption': instance.caption,
      'isPublished': instance.isPublished,
      'createdAt': instance.createdAt.toIso8601String(),
      'trip': instance.trip,
    };

Media _$MediaFromJson(Map<String, dynamic> json) => Media(
      id: json['id'] as String,
      url: json['url'] as String,
      publicId: json['publicId'] as String,
      type: $enumDecode(_$MediaTypeEnumMap, json['type']),
      filename: json['filename'] as String?,
      size: (json['size'] as num?)?.toInt(),
      width: (json['width'] as num?)?.toInt(),
      height: (json['height'] as num?)?.toInt(),
      duration: (json['duration'] as num?)?.toDouble(),
      processingStatus: $enumDecodeNullable(
              _$MediaProcessingStatusEnumMap, json['processingStatus']) ??
          MediaProcessingStatus.completed,
      uploadedById: json['uploadedById'] as String,
      tripId: json['tripId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );

Map<String, dynamic> _$MediaToJson(Media instance) => <String, dynamic>{
      'id': instance.id,
      'url': instance.url,
      'publicId': instance.publicId,
      'type': _$MediaTypeEnumMap[instance.type]!,
      'filename': instance.filename,
      'size': instance.size,
      'width': instance.width,
      'height': instance.height,
      'duration': instance.duration,
      'processingStatus':
          _$MediaProcessingStatusEnumMap[instance.processingStatus]!,
      'uploadedById': instance.uploadedById,
      'tripId': instance.tripId,
      'createdAt': instance.createdAt.toIso8601String(),
    };

const _$MediaTypeEnumMap = {
  MediaType.image: 'IMAGE',
  MediaType.video: 'VIDEO',
};

const _$MediaProcessingStatusEnumMap = {
  MediaProcessingStatus.pending: 'PENDING',
  MediaProcessingStatus.processing: 'PROCESSING',
  MediaProcessingStatus.completed: 'COMPLETED',
  MediaProcessingStatus.failed: 'FAILED',
};

GpsCoordinates _$GpsCoordinatesFromJson(Map<String, dynamic> json) =>
    GpsCoordinates(
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
    );

Map<String, dynamic> _$GpsCoordinatesToJson(GpsCoordinates instance) =>
    <String, dynamic>{
      'lat': instance.lat,
      'lng': instance.lng,
    };

CreateTripRequest _$CreateTripRequestFromJson(Map<String, dynamic> json) =>
    CreateTripRequest(
      title: json['title'] as String,
      description: json['description'] as String?,
      startDate: json['startDate'] == null
          ? null
          : DateTime.parse(json['startDate'] as String),
      endDate: json['endDate'] == null
          ? null
          : DateTime.parse(json['endDate'] as String),
      destinations: (json['destinations'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      destinationPlaceIds: (json['destinationPlaceIds'] as List<dynamic>)
          .map((e) => e as String)
          .toList(),
      mood: $enumDecodeNullable(_$TripMoodEnumMap, json['mood']),
      type: $enumDecodeNullable(_$TripTypeEnumMap, json['type']),
      coverMediaId: json['coverMediaId'] as String?,
    );

Map<String, dynamic> _$CreateTripRequestToJson(CreateTripRequest instance) =>
    <String, dynamic>{
      'title': instance.title,
      'description': instance.description,
      'startDate': instance.startDate?.toIso8601String(),
      'endDate': instance.endDate?.toIso8601String(),
      'destinations': instance.destinations,
      'destinationPlaceIds': instance.destinationPlaceIds,
      'mood': _$TripMoodEnumMap[instance.mood],
      'type': _$TripTypeEnumMap[instance.type],
      'coverMediaId': instance.coverMediaId,
    };

CreateThreadEntryRequest _$CreateThreadEntryRequestFromJson(
        Map<String, dynamic> json) =>
    CreateThreadEntryRequest(
      type: $enumDecode(_$ThreadEntryTypeEnumMap, json['type']),
      contentText: json['contentText'] as String?,
      mediaId: json['mediaId'] as String?,
      locationName: json['locationName'] as String?,
      gpsCoordinates: json['gpsCoordinates'] == null
          ? null
          : GpsCoordinates.fromJson(
              json['gpsCoordinates'] as Map<String, dynamic>),
      placeId: json['placeId'] as String?,
      taggedUserIds: (json['taggedUserIds'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
      taggedUsernames: (json['taggedUsernames'] as List<dynamic>?)
          ?.map((e) => e as String)
          .toList(),
    );

Map<String, dynamic> _$CreateThreadEntryRequestToJson(
        CreateThreadEntryRequest instance) =>
    <String, dynamic>{
      'type': _$ThreadEntryTypeEnumMap[instance.type]!,
      'contentText': instance.contentText,
      'mediaId': instance.mediaId,
      'locationName': instance.locationName,
      'gpsCoordinates': instance.gpsCoordinates,
      'placeId': instance.placeId,
      'taggedUserIds': instance.taggedUserIds,
      'taggedUsernames': instance.taggedUsernames,
    };
