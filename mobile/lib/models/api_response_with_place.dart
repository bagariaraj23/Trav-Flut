import 'package:tripthread/models/place.dart';

class ApiResponseWithPlace {
  final bool success;
  final Place? place;
  final String placeId;

  ApiResponseWithPlace({
    required this.success,
    this.place,
    required this.placeId,
  });
}
