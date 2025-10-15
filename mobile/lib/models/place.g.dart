// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'place.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Place _$PlaceFromJson(Map<String, dynamic> json) => Place(
      id: json['id'] as String,
      name: json['name'] as String,
      address: json['address'] as String?,
      lat: (json['lat'] as num).toDouble(),
      lng: (json['lng'] as num).toDouble(),
      placeType: $enumDecodeNullable(_$PlaceTypeEnumMap, json['placeType']) ??
          PlaceType.poi,
      source: $enumDecodeNullable(_$PlaceSourceEnumMap, json['source']) ??
          PlaceSource.user,
      externalId: json['externalId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );

Map<String, dynamic> _$PlaceToJson(Place instance) => <String, dynamic>{
      'id': instance.id,
      'name': instance.name,
      'address': instance.address,
      'lat': instance.lat,
      'lng': instance.lng,
      'placeType': _$PlaceTypeEnumMap[instance.placeType]!,
      'source': _$PlaceSourceEnumMap[instance.source]!,
      'externalId': instance.externalId,
      'createdAt': instance.createdAt.toIso8601String(),
      'updatedAt': instance.updatedAt.toIso8601String(),
    };

const _$PlaceTypeEnumMap = {
  PlaceType.poi: 'POI',
  PlaceType.stay: 'STAY',
  PlaceType.food: 'FOOD',
  PlaceType.transport: 'TRANSPORT',
  PlaceType.viewpoint: 'VIEWPOINT',
  PlaceType.other: 'OTHER',
};

const _$PlaceSourceEnumMap = {
  PlaceSource.user: 'USER',
  PlaceSource.google: 'GOOGLE',
  PlaceSource.mapbox: 'MAPBOX',
  PlaceSource.apple: 'APPLE',
};

PlaceOnTrip _$PlaceOnTripFromJson(Map<String, dynamic> json) => PlaceOnTrip(
      id: json['id'] as String,
      tripId: json['tripId'] as String,
      placeId: json['placeId'] as String,
      visitedAt: json['visitedAt'] == null
          ? null
          : DateTime.parse(json['visitedAt'] as String),
      dayIndex: (json['dayIndex'] as num?)?.toInt(),
      notes: json['notes'] as String?,
      order: (json['order'] as num?)?.toInt(),
      place: Place.fromJson(json['place'] as Map<String, dynamic>),
    );

Map<String, dynamic> _$PlaceOnTripToJson(PlaceOnTrip instance) =>
    <String, dynamic>{
      'id': instance.id,
      'tripId': instance.tripId,
      'placeId': instance.placeId,
      'visitedAt': instance.visitedAt?.toIso8601String(),
      'dayIndex': instance.dayIndex,
      'notes': instance.notes,
      'order': instance.order,
      'place': instance.place,
    };
