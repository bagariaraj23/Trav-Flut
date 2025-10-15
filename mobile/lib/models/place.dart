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
