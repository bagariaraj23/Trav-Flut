class DateUtils {
  /// Normalizes a date to UTC midnight (00:00:00 UTC)
  static DateTime normalizeToUtcMidnight(DateTime date) {
    return DateTime.utc(date.year, date.month, date.day);
  }

  /// Converts a date to a date-only string (YYYY-MM-DD) in UTC
  static String toUtcDateString(DateTime date) {
    final normalized = normalizeToUtcMidnight(date);
    return normalized.toIso8601String().split('T')[0];
  }

  /// Extracts only the date components from a DateTime for display
  static DateTime extractDateOnly(DateTime dateTime) {
    final utcDate = dateTime.isUtc
        ? dateTime
        : DateTime.utc(dateTime.year, dateTime.month, dateTime.day);

    return DateTime(utcDate.year, utcDate.month, utcDate.day);
  }

  /// Formats a date for display, ensuring correct date regardless of timezone
  static String formatDateForDisplay(DateTime dateTime) {
    final dateOnly = extractDateOnly(dateTime);
    final months = [
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
    return '${months[dateOnly.month - 1]} ${dateOnly.day}, ${dateOnly.year}';
  }
}
