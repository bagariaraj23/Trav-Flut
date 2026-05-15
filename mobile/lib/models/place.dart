import 'package:json_annotation/json_annotation.dart';

part 'place.g.dart';

@JsonSerializable()
class Place {
  final String id;
  final String name;
  final String? address;
  final double lat;
  final double lng;
  @JsonKey(name: 'placeType')
  final PlaceType placeType;
  @JsonKey(name: 'source')
  final PlaceSource source;
  final String? externalId;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Place({
    required this.id,
    required this.name,
    this.address,
    required this.lat,
    required this.lng,
    this.placeType = PlaceType.poi,
    this.source = PlaceSource.user,
    this.externalId,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Place.fromJson(Map<String, dynamic> json) => _$PlaceFromJson(json);
  Map<String, dynamic> toJson() => _$PlaceToJson(this);
}

@JsonSerializable()
class PlaceOnTrip {
  final String id;
  final String tripId;
  final String placeId;
  final DateTime? visitedAt;
  final int? dayIndex;
  final String? notes;
  final int? order;
  final Place place;

  const PlaceOnTrip({
    required this.id,
    required this.tripId,
    required this.placeId,
    this.visitedAt,
    this.dayIndex,
    this.notes,
    this.order,
    required this.place,
  });

  factory PlaceOnTrip.fromJson(Map<String, dynamic> json) =>
      _$PlaceOnTripFromJson(json);
  Map<String, dynamic> toJson() => _$PlaceOnTripToJson(this);
}

@JsonEnum()
enum PlaceType {
  @JsonValue('POI')
  poi,
  @JsonValue('STAY')
  stay,
  @JsonValue('FOOD')
  food,
  @JsonValue('TRANSPORT')
  transport,
  @JsonValue('VIEWPOINT')
  viewpoint,
  @JsonValue('OTHER')
  other,
}

@JsonEnum()
enum PlaceSource {
  @JsonValue('USER')
  user,
  @JsonValue('GOOGLE')
  google,
  @JsonValue('MAPBOX')
  mapbox,
  @JsonValue('APPLE')
  apple,
}

@JsonEnum()
enum MapPlaceOrigin {
  @JsonValue('DESTINATION')
  destination,
  @JsonValue('THREAD_ENTRY')
  threadEntry,
  @JsonValue('ON_TRIP')
  onTrip,
}

@JsonSerializable()
class MapPlace {
  final Place place;
  final MapPlaceOrigin origin;
  final int? destinationIndex;
  final String? threadEntryId;
  final DateTime? visitedAt;
  final int? dayIndex;
  final int? order;
  final String? placeOnTripId;
  final String? notes;
  final DateTime? createdAt;

  const MapPlace({
    required this.place,
    required this.origin,
    this.destinationIndex,
    this.threadEntryId,
    this.visitedAt,
    this.dayIndex,
    this.order,
    this.placeOnTripId,
    this.notes,
    this.createdAt,
  });

  factory MapPlace.fromJson(Map<String, dynamic> json) =>
      _$MapPlaceFromJson(json);
  Map<String, dynamic> toJson() => _$MapPlaceToJson(this);

  factory MapPlace.fromPlaceOnTrip(PlaceOnTrip pot) => MapPlace(
        place: pot.place,
        origin: MapPlaceOrigin.onTrip,
        visitedAt: pot.visitedAt,
        dayIndex: pot.dayIndex,
        notes: pot.notes,
        order: pot.order,
        placeOnTripId: pot.id,
      );
}

@JsonSerializable()
class ResolvedPlaceResponse {
  final Place place;

  const ResolvedPlaceResponse({
    required this.place,
  });

  factory ResolvedPlaceResponse.fromJson(Map<String, dynamic> json) =>
      _$ResolvedPlaceResponseFromJson(json);
  Map<String, dynamic> toJson() => _$ResolvedPlaceResponseToJson(this);
}
