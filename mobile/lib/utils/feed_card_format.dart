import 'package:intl/intl.dart';
import 'package:tripthread/models/trip.dart';
import 'package:tripthread/utils/locale_dates.dart';

/// Compact trip window for feed card headers, e.g. `12–18 Oct · 7 days`.
String formatFeedTripWindow(Trip? trip) {
  final start = trip?.startDate;
  final end = trip?.endDate;
  if (start == null && end == null) return 'Dates not set';

  final localStart = start?.toLocal();
  final localEnd = end?.toLocal();

  if (localStart != null && localEnd != null) {
    final days = localEnd.difference(localStart).inDays.abs() + 1;
    final sameMonth =
        localStart.year == localEnd.year && localStart.month == localEnd.month;
    final sameYear = localStart.year == localEnd.year;
    final month = DateFormat.MMM(LocaleDates.localeName()).format(localStart);
    final endMonth = DateFormat.MMM(LocaleDates.localeName()).format(localEnd);
    String range;
    if (sameMonth) {
      range = '${localStart.day}–${localEnd.day} $month';
    } else if (sameYear) {
      range = '${localStart.day} $month – ${localEnd.day} $endMonth';
    } else {
      range =
          '${LocaleDates.mediumDate(localStart)} – ${LocaleDates.mediumDate(localEnd)}';
    }
    return '$range · $days ${days == 1 ? 'day' : 'days'}';
  }

  if (localStart != null) {
    return '${LocaleDates.mediumDate(localStart)} · Until you end it';
  }
  return 'Until ${LocaleDates.mediumDate(localEnd!)}';
}

/// Destination chain: `Jaipur → Pushkar → Udaipur`. Single name if one stop.
String formatFeedRoute(List<String>? destinations) {
  final cleaned = (destinations ?? [])
      .map((d) => d.trim())
      .where((d) => d.isNotEmpty)
      .toList();
  if (cleaned.isEmpty) return '';
  if (cleaned.length == 1) return cleaned.first;
  return cleaned.join(' → ');
}

String templateChoiceApiValue(FinalPostTemplateChoice choice) {
  switch (choice) {
    case FinalPostTemplateChoice.postcard:
      return 'postcard';
    case FinalPostTemplateChoice.mapFirst:
      return 'map_first';
    case FinalPostTemplateChoice.threadReel:
      return 'thread_reel';
  }
}
