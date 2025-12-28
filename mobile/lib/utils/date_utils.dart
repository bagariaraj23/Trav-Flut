/// Date utility functions for handling timezone issues
class DateUtils {
  /// Normalizes a date to UTC midnight (00:00:00 UTC)
  /// This ensures dates are stored consistently regardless of timezone
  static DateTime normalizeToUtcMidnight(DateTime date) {
    // Extract only the date components (year, month, day)
    // Create a new DateTime in UTC at midnight
    return DateTime.utc(date.year, date.month, date.day);
  }

  /// Converts a date to a date-only string (YYYY-MM-DD) in UTC
  /// This is used when sending dates to the backend
  static String toUtcDateString(DateTime date) {
    final normalized = normalizeToUtcMidnight(date);
    return normalized.toIso8601String().split('T')[0];
  }

  /// Extracts only the date components from a DateTime for display
  /// This ignores time and timezone, showing only the date
  static DateTime extractDateOnly(DateTime dateTime) {
    // If the dateTime is already in UTC, use it directly
    // Otherwise, convert to UTC first, then extract date
    final utcDate = dateTime.isUtc 
        ? dateTime 
        : DateTime.utc(dateTime.year, dateTime.month, dateTime.day);
    
    // Return a local DateTime with just the date components
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
      'Dec'
    ];
    return '${months[dateOnly.month - 1]} ${dateOnly.day}, ${dateOnly.year}';
  }
}

