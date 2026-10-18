class ZoneClock {
  final DateTime local;
  final String label;

  const ZoneClock({required this.local, required this.label});
}

typedef ZoneConverter = ZoneClock Function(DateTime utc);

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

bool isLegacyDateOnly(DateTime instant, {String? scheduleTimezone}) {
  if (scheduleTimezone != null && scheduleTimezone.isNotEmpty) return false;
  final utc = instant.toUtc();
  return utc.hour == 0 &&
      utc.minute == 0 &&
      utc.second == 0 &&
      utc.millisecond == 0 &&
      utc.microsecond == 0;
}

/// UTC instants render in the viewer's zone. Legacy midnight rows stay a calendar date.
String formatTripInstant(
  DateTime instant, {
  String? scheduleTimezone,
  ZoneConverter? convert,
}) {
  final utc = instant.toUtc();
  if (isLegacyDateOnly(utc, scheduleTimezone: scheduleTimezone)) {
    return '${utc.day} ${_months[utc.month - 1]} ${utc.year}';
  }

  final clock = convert?.call(utc) ??
      ZoneClock(local: utc.toLocal(), label: utc.toLocal().timeZoneName);
  final local = clock.local;
  final hour12 = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  final period = local.hour >= 12 ? 'PM' : 'AM';
  final zone = clock.label.isEmpty ? '' : ' ${clock.label}';
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $hour12:$minute $period$zone';
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
  final local = instant.toLocal();
  return '${local.day}/${local.month}/${local.year}';
}
