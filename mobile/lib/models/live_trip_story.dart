import 'package:tripthread/models/trip.dart';
import 'package:tripthread/models/user.dart';

/// Home "Happening Now" story circle: a traveller + their live trip.
class LiveTripStory {
  final bool isSelf;
  final User user;
  final Trip trip;

  const LiveTripStory({
    required this.isSelf,
    required this.user,
    required this.trip,
  });

  factory LiveTripStory.fromJson(Map<String, dynamic> json) {
    return LiveTripStory(
      isSelf: json['isSelf'] as bool? ?? false,
      user: User.fromJson(json['user'] as Map<String, dynamic>),
      trip: Trip.fromJson(json['trip'] as Map<String, dynamic>),
    );
  }
}
