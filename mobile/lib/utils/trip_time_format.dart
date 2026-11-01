import 'package:tripthread/utils/locale_dates.dart';

class ZoneClock {
  final DateTime local;
  final String label;

  const ZoneClock({required this.local, required this.label});
}

typedef ZoneConverter = ZoneClock Function(DateTime utc);

bool isLegacyDateOnly(DateTime instant, {String? scheduleTimezone}) {
  if (scheduleTimezone != null && scheduleTimezone.isNotEmpty) return false;
  final utc = instant.toUtc();
  return utc.hour == 0 &&
      utc.minute == 0 &&
      utc.second == 0 &&
      utc.millisecond == 0 &&
      utc.microsecond == 0;
}

/// UTC instants render in the viewer's zone and the device region's date order.
/// Legacy midnight rows stay the stored calendar date, without a clock time.
String formatTripInstant(
  DateTime instant, {
  String? scheduleTimezone,
  ZoneConverter? convert,
}) {
  final utc = instant.toUtc();
  if (isLegacyDateOnly(utc, scheduleTimezone: scheduleTimezone)) {
    return LocaleDates.mediumDate(DateTime.utc(utc.year, utc.month, utc.day));
  }

  final clock = convert?.call(utc) ??
      ZoneClock(local: utc.toLocal(), label: utc.toLocal().timeZoneName);
  final local = clock.local;
  final zone = clock.label.isEmpty ? '' : ' ${clock.label}';
  return '${LocaleDates.mediumDate(local)}, ${LocaleDates.timeOfDay(local)}$zone';
}

String formatTripRange(
  DateTime? start,
  DateTime? end, {
  String? scheduleTimezone,
  ZoneConverter? convert,
}) {
  if (start == null && end == null) return 'Dates not set';
  if (start == null) {
    return 'Until ${formatTripInstant(end!, scheduleTimezone: scheduleTimezone, convert: convert)}';
  }
  final startLabel = formatTripInstant(
    start,
    scheduleTimezone: scheduleTimezone,
    convert: convert,
  );
  if (end == null) return '$startLabel · Until you end it';
  return '$startLabel – ${formatTripInstant(end, scheduleTimezone: scheduleTimezone, convert: convert)}';
}

String formatLocalDate(DateTime instant) {
  return LocaleDates.numericDate(instant.toLocal());
}
