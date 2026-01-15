import 'package:json_annotation/json_annotation.dart';
import 'package:tripthread/models/user.dart';
import 'package:tripthread/models/place.dart';

part 'trip.g.dart';

@JsonSerializable()
class Trip {
  final String id;
  final String userId;
  final String title;
  final String? description;
  final DateTime startDate;
  final DateTime endDate;
  @JsonKey(defaultValue: [])
  final List<String> destinations;
  final TripMood? mood;
  final TripType? type;
  final String? coverMediaId;
  final Media? coverMedia;
  final TripStatus status;
  @JsonKey(defaultValue: 0)
  final int entryCount;
  @JsonKey(defaultValue: 1)
  final int participantCount;
  final String? startLocationId;
  final Place? startLocation;
  final String? endLocationId;
  final Place? endLocation;
  final List<PlaceOnTrip>? placeVisits;
  final DateTime createdAt;
  final DateTime updatedAt;
  final User? user;
  final List<TripParticipant>? participants;
  final List<TripThreadEntry>? threadEntries;
  final TripFinalPost? finalPost;
  final TripCounts? counts;

  const Trip({
    required this.id,
    required this.userId,
    required this.title,
    this.description,
    required this.startDate,
    required this.endDate,
    required this.destinations,
    this.mood,
    this.type,
    this.coverMediaId,
    this.coverMedia,
    required this.status,
    required this.entryCount,
    required this.participantCount,
    this.startLocationId,
    this.startLocation,
    this.endLocationId,
    this.endLocation,
    this.placeVisits,
    required this.createdAt,
    required this.updatedAt,
    this.user,
    this.participants,
    this.threadEntries,
    this.finalPost,
    this.counts,
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
    String? coverMediaId,
    Media? coverMedia,
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
      coverMediaId: coverMediaId ?? this.coverMediaId,
      coverMedia: coverMedia ?? this.coverMedia,
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
  final String? mediaId;
  final String? locationName;
  final GpsCoordinates? gpsCoordinates;
  final String? placeId;
  final Place? place;
  final DateTime createdAt;
  final User author;
  final List<User>? taggedUsers;
  final Media? media;
  @JsonKey(defaultValue: 0)
  final int likeCount;
  @JsonKey(defaultValue: 0)
  final int commentCount;
  @JsonKey(defaultValue: false)
  final bool hasLiked;

  const TripThreadEntry({
    required this.id,
    required this.tripId,
    required this.authorId,
    required this.type,
    this.contentText,
    this.mediaId,
    this.locationName,
    this.gpsCoordinates,
    this.placeId,
    this.place,
    required this.createdAt,
    required this.author,
    this.taggedUsers,
    this.media,
    this.likeCount = 0,
    this.commentCount = 0,
    this.hasLiked = false,
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
  final String? coverMediaUrl;
  final GenerationStatus generationStatus;
  final bool isPublished;
  final DateTime? publishedAt;
  final DateTime createdAt;
  final DateTime updatedAt;
  final Trip? trip;
  @JsonKey(defaultValue: 0)
  final int likeCount;
  @JsonKey(defaultValue: 0)
  final int commentCount;
  @JsonKey(defaultValue: 0)
  final int shareCount;
  @JsonKey(defaultValue: false)
  final bool hasLiked;

  const TripFinalPost({
    required this.id,
    required this.tripId,
    required this.summaryText,
    required this.curatedMedia,
    this.caption,
    this.coverMediaUrl,
    this.generationStatus = GenerationStatus.draft,
    required this.isPublished,
    this.publishedAt,
    required this.createdAt,
    required this.updatedAt,
    this.trip,
    this.likeCount = 0,
    this.commentCount = 0,
    this.shareCount = 0,
    this.hasLiked = false,
  });

  factory TripFinalPost.fromJson(Map<String, dynamic> json) =>
      _$TripFinalPostFromJson(json);
  Map<String, dynamic> toJson() => _$TripFinalPostToJson(this);

  TripFinalPost copyWith({
    String? id,
    String? tripId,
    String? summaryText,
    List<String>? curatedMedia,
    String? caption,
    String? coverMediaUrl,
    GenerationStatus? generationStatus,
    bool? isPublished,
    DateTime? publishedAt,
    DateTime? createdAt,
    DateTime? updatedAt,
    Trip? trip,
    int? likeCount,
    int? commentCount,
    int? shareCount,
    bool? hasLiked,
  }) {
    return TripFinalPost(
      id: id ?? this.id,
      tripId: tripId ?? this.tripId,
      summaryText: summaryText ?? this.summaryText,
      curatedMedia: curatedMedia ?? this.curatedMedia,
      caption: caption ?? this.caption,
      coverMediaUrl: coverMediaUrl ?? this.coverMediaUrl,
      generationStatus: generationStatus ?? this.generationStatus,
      isPublished: isPublished ?? this.isPublished,
      publishedAt: publishedAt ?? this.publishedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      trip: trip ?? this.trip,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      shareCount: shareCount ?? this.shareCount,
      hasLiked: hasLiked ?? this.hasLiked,
    );
  }
}

@JsonSerializable()
class Media {
  final String id;
  final String url;
  final String publicId;
  final MediaType type;
  final String? filename;
  final int? size;
  final int? width;
  final int? height;
  final double? duration;
  final MediaProcessingStatus processingStatus;
  final String uploadedById;
  final String? tripId;
  final DateTime createdAt;

  const Media({
    required this.id,
    required this.url,
    required this.publicId,
    required this.type,
    this.filename,
    this.size,
    this.width,
    this.height,
    this.duration,
    this.processingStatus = MediaProcessingStatus.completed,
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

  const GpsCoordinates({required this.lat, required this.lng});

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

enum MediaProcessingStatus {
  @JsonValue('PENDING')
  pending,
  @JsonValue('PROCESSING')
  processing,
  @JsonValue('COMPLETED')
  completed,
  @JsonValue('FAILED')
  failed,
}

enum GenerationStatus {
  @JsonValue('DRAFT')
  draft,
  @JsonValue('GENERATING')
  generating,
  @JsonValue('READY')
  ready,
  @JsonValue('PUBLISHED')
  published,
  @JsonValue('FAILED')
  failed,
}

// Request DTOs
@JsonSerializable()
class CreateTripRequest {
  final String title;
  final String? description;
  final DateTime? startDate;
  final DateTime? endDate;
  final List<String> destinations;
  final List<String> destinationPlaceIds;
  final TripMood? mood;
  final TripType? type;
  final String? coverMediaId;

  const CreateTripRequest({
    required this.title,
    this.description,
    this.startDate,
    this.endDate,
    required this.destinations,
    required this.destinationPlaceIds,
    this.mood,
    this.type,
    this.coverMediaId,
  });

  factory CreateTripRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateTripRequestFromJson(json);

  Map<String, dynamic> toJson() {
    final normalizedStartDate = startDate != null
        ? DateTime.utc(startDate!.year, startDate!.month, startDate!.day)
        : null;
    final normalizedEndDate = endDate != null
        ? DateTime.utc(endDate!.year, endDate!.month, endDate!.day)
        : null;

    final baseJson = _$CreateTripRequestToJson(this);
    if (normalizedStartDate != null) {
      baseJson['startDate'] = normalizedStartDate.toIso8601String();
    }
    if (normalizedEndDate != null) {
      baseJson['endDate'] = normalizedEndDate.toIso8601String();
    }
    return baseJson;
  }
}

@JsonSerializable()
class CreateThreadEntryRequest {
  final ThreadEntryType type;
  final String? contentText;
  final String? mediaId;
  final String? locationName;
  final GpsCoordinates? gpsCoordinates;
  final String? placeId;
  final List<String>? taggedUserIds;
  final List<String>? taggedUsernames;

  const CreateThreadEntryRequest({
    required this.type,
    this.contentText,
    this.mediaId,
    this.locationName,
    this.gpsCoordinates,
    this.placeId,
    this.taggedUserIds,
    this.taggedUsernames,
  });

  factory CreateThreadEntryRequest.fromJson(Map<String, dynamic> json) =>
      _$CreateThreadEntryRequestFromJson(json);
  Map<String, dynamic> toJson() => _$CreateThreadEntryRequestToJson(this);
}

@JsonSerializable()
class TripConflictInfo {
  final bool hasOngoingTrip;
  final bool hasFutureTrip;
  final TripConflictTrip? ongoingTrip;
  final TripConflictTrip? futureTrip;

  const TripConflictInfo({
    required this.hasOngoingTrip,
    required this.hasFutureTrip,
    this.ongoingTrip,
    this.futureTrip,
  });

  factory TripConflictInfo.fromJson(Map<String, dynamic> json) =>
      _$TripConflictInfoFromJson(json);
  Map<String, dynamic> toJson() => _$TripConflictInfoToJson(this);
}

@JsonSerializable()
class TripConflictTrip {
  final String id;
  final String title;
  final DateTime startDate;
  final DateTime? endDate;
  final TripStatus status;

  const TripConflictTrip({
    required this.id,
    required this.title,
    required this.startDate,
    this.endDate,
    required this.status,
  });

  factory TripConflictTrip.fromJson(Map<String, dynamic> json) =>
      _$TripConflictTripFromJson(json);
  Map<String, dynamic> toJson() => _$TripConflictTripToJson(this);
}
