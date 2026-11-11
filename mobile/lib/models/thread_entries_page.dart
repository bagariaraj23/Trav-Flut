import 'package:tripthread/models/trip.dart';

/// Paginated thread entries (newest page first; [items] chronological ascending).
class ThreadEntriesPage {
  final List<TripThreadEntry> items;
  final bool hasMoreOlder;
  final String? nextOlderCursor;

  const ThreadEntriesPage({
    required this.items,
    required this.hasMoreOlder,
    this.nextOlderCursor,
  });

  factory ThreadEntriesPage.fromJson(Map<String, dynamic> json) {
    final raw = json['items'];
    final list = raw is List
        ? raw
            .map(
              (e) => TripThreadEntry.fromJson(e as Map<String, dynamic>),
            )
            .toList()
        : <TripThreadEntry>[];
    return ThreadEntriesPage(
      items: list,
      hasMoreOlder: json['hasMoreOlder'] as bool? ?? false,
      nextOlderCursor: json['nextOlderCursor'] as String?,
    );
  }
}
