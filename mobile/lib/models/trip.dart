import 'package:json_annotation/json_annotation.dart';
import 'package:tripthread/models/user.dart';

part 'trip.g.dart';

@JsonSerializable()
class Trip {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> destinations;
  final TripMood? mood;
  final TripType? type;
  final String? coverMediaUrl;
  final TripStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? user;
  final List<TripParticipant>? participants;
  final List<TripThreadEntry>? threadEntries;
  final TripFinalPost? finalPost;
  final TripCounts? counts;
  final int? entryCount;
  final int? participantCount;

  const Trip({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    required this.destinations,
    this.mood,
    this.type,
    this.coverMediaUrl,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.participants,
    this.threadEntries,
    this.finalPost,
    this.counts,
    this.entryCount,
    this.participantCount,
  });

  factory Trip.fromJson(Map<String, dynamic> json) => _$TripFromJson(json);
  Map<String, dynamic> toJson() => _$TripToJson(this);

  Trip copyWith({
    String? id,
    String? userId,
    String? title,
    String? description,
    DateTime? startDate,
    DateTime? endDate,
    List<String>? destinations,
    TripMood? mood,
    TripType? type,
    String? coverMediaUrl,
    TripStatus? status,
    DateTime? createdAt,
    DateTime? updatedAt,
    User? user,
    List<TripParticipant>? participants,
    List<TripThreadEntry>? threadEntries,
    TripFinalPost? finalPost,
    TripCounts? counts,
    int? entryCount,
    int? participantCount,
  }) {
    return Trip(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      title: title ?? this.title,
      description: description ?? this.description,
      startDate: startDate ?? this.startDate,
      endDate: endDate ?? this.endDate,
      destinations: destinations ?? this.destinations,
      mood: mood ?? this.mood,
      type: type ?? this.type,
      coverMediaUrl: coverMediaUrl ?? this.coverMediaUrl,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      user: user ?? this.user,
      participants: participants ?? this.participants,
      threadEntries: threadEntries ?? this.threadEntries,
      finalPost: finalPost ?? this.finalPost,
      counts: counts ?? this.counts,
      entryCount: entryCount ?? this.entryCount,
      participantCount: participantCount ?? this.participantCount,
    );
  }
}

@JsonSerializable()
class TripCounts {
  final int threadEntries;
  final int media;
  final int participants;

  const TripCounts({
    required this.threadEntries,
    required this.media,
    required this.participants,
  });

  factory TripCounts.fromJson(Map<String, dynamic> json) =>
      _$TripCountsFromJson(json);
  Map<String, dynamic> toJson() => _$TripCountsToJson(this);
}

@JsonSerializable()
class TripParticipant {
  final String id;
  final String tripId;
  final String userId;
  final String role;
  final DateTime joinedAt;
  final User? user;

  const TripParticipant({
    required this.id,
    required this.tripId,
    required this.userId,
    required this.role,
    required this.joinedAt,
    this.user,
  });

  factory TripParticipant.fromJson(Map<String, dynamic> json) =>
      _$TripParticipantFromJson(json);
  Map<String, dynamic> toJson() => _$TripParticipantToJson(this);
}

@JsonSerializable()
class TripThreadEntry {
  final String id;
  final String tripId;
  final String authorId;
  final ThreadEntryType type;
  final String? contentText;
  final String? mediaUrl;
  final String? locationName;
  final GpsCoordinates? gpsCoordinates;
  final DateTime createdAt;
  final User author;
  final List<User>? taggedUsers;
  final Media? media;

  const TripThreadEntry({
    required this.id,
    required this.tripId,
    required this.authorId,
    required this.type,
    this.contentText,
    this.mediaUrl,
    this.locationName,
    this.gpsCoordinates,
    required this.createdAt,
    required this.author,
    this.taggedUsers,
    this.media,
  });

  factory TripThreadEntry.fromJson(Map<String, dynamic> json) =>
      _$TripThreadEntryFromJson(json);
  Map<String, dynamic> toJson() => _$TripThreadEntryToJson(this);
}

@JsonSerializable()
class TripFinalPost {
  final String id;
  final String tripId;
  final String summaryText;
  final List<String> curatedMedia;
  final String? caption;
  final bool isPublished;
  final DateTime createdAt;
  final Trip? trip;

  const TripFinalPost({
    required this.id,
    required this.tripId,
    required this.summaryText,
    required this.curatedMedia,
    this.caption,
    required this.isPublished,
    required this.createdAt,
    this.trip,
  });

  factory TripFinalPost.fromJson(Map<String, dynamic> json) =>
      _$TripFinalPostFromJson(json);
  Map<String, dynamic> toJson() => _$TripFinalPostToJson(this);
}

@JsonSerializable()
class Media {
  final String id;
  final String url;
  final MediaType type;
  final String? filename;
  final int? size;
  final String uploadedById;
  final String? tripId;
  final DateTime createdAt;

  const Media({
    required this.id,
    required this.url,
    required this.type,
    this.filename,
    this.size,
    required this.uploadedById,
    this.tripId,
    required this.createdAt,
  });

  factory Media.fromJson(Map<String, dynamic> json) => _$MediaFromJson(json);
  Map<String, dynamic> toJson() => _$MediaToJson(this);
}

@JsonSerializable()
class GpsCoordinates {
  final double lat;
  final double lng;

  const GpsCoordinates({
    required this.lat,
    required this.lng,
  });

  factory GpsCoordinates.fromJson(Map<String, dynamic> json) =>
      _$GpsCoordinatesFromJson(json);
  Map<String, dynamic> toJson() => _$GpsCoordinatesToJson(this);
}

enum TripStatus {
  @JsonValue('UPCOMING')
  upcoming,
  @JsonValue('ONGOING')
  ongoing,
  @JsonValue('ENDED')
  ended,
}

enum TripMood {
  @JsonValue('RELAXED')
  relaxed,
  @JsonValue('ADVENTURE')
  adventure,
  @JsonValue('SPIRITUAL')
  spiritual,
  @JsonValue('CULTURAL')
  cultural,
  @JsonValue('PARTY')
  party,
  @JsonValue('MIXED')
  mixed,
}

enum TripType {
  @JsonValue('SOLO')
  solo,
  @JsonValue('GROUP')
  group,
  @JsonValue('COUPLE')
  couple,
  @JsonValue('FAMILY')
  family,
}

enum ThreadEntryType {
  @JsonValue('TEXT')
  text,
  @JsonValue('MEDIA')
  media,
  @JsonValue('LOCATION')
  location,
  @JsonValue('CHECKIN')
  checkin,
}

enum MediaType {
  @JsonValue('IMAGE')
  image,
  @JsonValue('VIDEO')
  video,
}

// Request DTOs
@JsonSerializable()
class CreateTripRequest {
  final String title;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> destinations;
  final TripMood? mood;
  final TripType? type;
  final String? coverMediaUrl;

  const CreateTripRequest({
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    required this.destinations,
    this.mood,
    this.type,
    this.coverMediaUrl,
  });

  factory CreateTripRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateTripRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateTripRequestToJson(this);
}

@JsonSerializable()
class CreateThreadEntryRequest {
  final ThreadEntryType type;
  final String? contentText;
  final String? mediaUrl;
  final String? locationName;
  final GpsCoordinates? gpsCoordinates;
  final List<String>? taggedUserIds;

  const CreateThreadEntryRequest({
    required this.type,
    this.contentText,
    this.mediaUrl,
    this.locationName,
    this.gpsCoordinates,
    this.taggedUserIds,
  });

  factory CreateThreadEntryRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateThreadEntryRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateThreadEntryRequestToJson(this);
}
