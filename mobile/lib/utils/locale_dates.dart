import 'dart:ui';

import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// Formats dates and times with the phone's language and region.
///
/// The device locale is the source of the country: English (India) is
/// `en_IN` (20/3/2026, 20 Mar 2026), English (United States) is `en_US`
/// (3/20/2026, Mar 20, 2026), English (United Kingdom) is `en_GB`
/// (20/03/2026, 24-hour time). These methods print the calendar fields on
/// [date] as given. Callers convert an instant with [DateTime.toLocal]
/// first when the value is a moment rather than a stored calendar day.
class LocaleDates {
  static String? debugLocaleOverride;
  static bool _initialized = false;
  static final Map<String, String> _resolved = {};

  static String localeName() {
    final override = debugLocaleOverride;
    if (override != null && override.isNotEmpty) {
      return override.replaceAll('-', '_');
    }
    final locale = PlatformDispatcher.instance.locale;
    final language = locale.languageCode;
    if (language.isEmpty) return 'en_US';
    final country = locale.countryCode;
    if (country == null || country.isEmpty) return language;
    return '${language}_$country';
  }

  /// Loads CLDR date symbols. [initializeDateFormatting] takes no notice of
  /// the locale argument and installs every locale, so one call is enough.
  static Future<void> ensureInitialized() async {
    await initializeDateFormatting();
    _initialized = true;
    _resolved.clear();
  }

  static String numericDate(DateTime date) =>
      _apply(date, DateFormat.yMd, _numericManual);

  static String monthDay(DateTime date) =>
      _apply(date, DateFormat.Md, _monthDayManual);

  static String mediumDate(DateTime date) =>
      _apply(date, DateFormat.yMMMd, _mediumManual);

  static String longDate(DateTime date) =>
      _apply(date, DateFormat.yMMMMd, _longManual);

  static String timeOfDay(DateTime date) =>
      _apply(date, DateFormat.jm, _timeManual);

  /// Month and day, then the clock. "20 Mar, 6:30 pm" or "Mar 20, 6:30 PM".
  static String mediumDateTime(DateTime date) {
    return '${_apply(date, DateFormat.MMMd, _mediumMonthDayManual)}, ${timeOfDay(date)}';
  }

  /// Chat list: clock today, "Yesterday", otherwise month and day.
  static String conversationStamp(DateTime instant, {DateTime? now}) {
    final wall = instant.toLocal();
    final clock = (now ?? DateTime.now()).toLocal();
    final day = DateTime(wall.year, wall.month, wall.day);
    final today = DateTime(clock.year, clock.month, clock.day);
    if (day == today) return timeOfDay(wall);
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return monthDay(wall);
  }

  /// Chat day divider: Today, Yesterday, or the long regional date.
  static String dayHeading(DateTime instant, {DateTime? now}) {
    final wall = instant.toLocal();
    final clock = (now ?? DateTime.now()).toLocal();
    final day = DateTime(wall.year, wall.month, wall.day);
    final today = DateTime(clock.year, clock.month, clock.day);
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return longDate(wall);
  }

  static String _apply(
    DateTime date,
    DateFormat Function(String locale) make,
    String Function(DateTime date, String locale) manual,
  ) {
    final requested = localeName();
    if (_initialized) {
      final locale = _formatLocale(requested);
      if (locale != null) return make(locale).format(date);
      return manual(date, requested);
    }
    try {
      return make(requested).format(date);
    } catch (error) {
      if (!_missingLocale(error)) rethrow;
      return manual(date, requested);
    }
  }

  static String? _formatLocale(String requested) {
    if (_initialized) {
      final cached = _resolved[requested];
      if (cached != null) return cached;
    }
    final parts = requested.split('_').where((part) => part.isNotEmpty).toList();
    final language = parts.isEmpty ? 'en' : parts.first;
    final country = parts.length > 1 ? parts[1] : '';
    // Do not drop a known country onto en_US. A Japanese or Indian locale with
    // no exact symbols falls through to the order table instead of month/day.
    final candidates = <String>[
      requested,
      language,
      if (country.isNotEmpty) 'en_$country',
      if (country.isEmpty || country.toUpperCase() == 'US') 'en_US',
    ];
    for (final candidate in candidates) {
      try {
        DateFormat.yMd(candidate).format(DateTime(2026, 1, 2));
        if (_initialized) _resolved[requested] = candidate;
        return candidate;
      } catch (error) {
        if (!_missingLocale(error)) rethrow;
        continue;
      }
    }
    return null;
  }

  static bool _missingLocale(Object error) {
    return error.runtimeType.toString() == 'LocaleDataException';
  }

  static _Order _order(String locale) {
    final parts = locale.split('_').where((part) => part.isNotEmpty).toList();
    final language = (parts.isEmpty ? 'en' : parts.first).toLowerCase();
    final country = parts.length > 1 ? parts[1].toUpperCase() : '';
    const monthFirst = {
      'US',
      'PH',
      'FM',
      'PW',
      'AS',
      'GU',
      'MH',
      'MP',
      'PR',
      'VI',
      'UM',
    };
    const yearFirst = {
      'CN',
      'JP',
      'KR',
      'KP',
      'TW',
      'HU',
      'LT',
      'MN',
      'CA',
      'SE',
      'ZA',
      'BT',
    };
    if (monthFirst.contains(country)) return _Order.monthDayYear;
    if (yearFirst.contains(country)) return _Order.yearMonthDay;
    if (country.isEmpty &&
        const {'zh', 'ja', 'ko', 'hu'}.contains(language)) {
      return _Order.yearMonthDay;
    }
    if (country.isEmpty && language == 'en') return _Order.monthDayYear;
    return _Order.dayMonthYear;
  }

  static bool _hour12(String locale) {
    final parts = locale.split('_');
    final country = parts.length > 1 ? parts[1].toUpperCase() : '';
    const twelve = {
      'US',
      'IN',
      'PH',
      'AU',
      'NZ',
      'EG',
      'SA',
      'PK',
      'BD',
      'MY',
      'CO',
    };
    if (twelve.contains(country)) return true;
    if (country.isEmpty && parts.first.toLowerCase() == 'en') return true;
    return false;
  }

  static String _numericManual(DateTime date, String locale) {
    final d = date.day;
    final m = date.month;
    final y = date.year;
    switch (_order(locale)) {
      case _Order.monthDayYear:
        return '$m/$d/$y';
      case _Order.yearMonthDay:
        return '$y/${m.toString().padLeft(2, '0')}/${d.toString().padLeft(2, '0')}';
      case _Order.dayMonthYear:
        return '${d.toString().padLeft(2, '0')}/${m.toString().padLeft(2, '0')}/$y';
    }
  }

  static String _monthDayManual(DateTime date, String locale) {
    switch (_order(locale)) {
      case _Order.monthDayYear:
        return '${date.month}/${date.day}';
      case _Order.yearMonthDay:
        return '${date.month}/${date.day}';
      case _Order.dayMonthYear:
        return '${date.day}/${date.month}';
    }
  }

  static String _mediumMonthDayManual(DateTime date, String locale) {
    final month = _shortMonths[date.month - 1];
    switch (_order(locale)) {
      case _Order.monthDayYear:
        return '$month ${date.day}';
      case _Order.yearMonthDay:
        return '$month ${date.day}';
      case _Order.dayMonthYear:
        return '${date.day} $month';
    }
  }

  static String _mediumManual(DateTime date, String locale) {
    final month = _shortMonths[date.month - 1];
    switch (_order(locale)) {
      case _Order.monthDayYear:
        return '$month ${date.day}, ${date.year}';
      case _Order.yearMonthDay:
        return '${date.year} $month ${date.day}';
      case _Order.dayMonthYear:
        return '${date.day} $month ${date.year}';
    }
  }

  static String _longManual(DateTime date, String locale) {
    final month = _longMonths[date.month - 1];
    switch (_order(locale)) {
      case _Order.monthDayYear:
        return '$month ${date.day}, ${date.year}';
      case _Order.yearMonthDay:
        return '${date.year} $month ${date.day}';
      case _Order.dayMonthYear:
        return '${date.day} $month ${date.year}';
    }
  }

  static String _timeManual(DateTime date, String locale) {
    final minute = date.minute.toString().padLeft(2, '0');
    if (!_hour12(locale)) {
      return '${date.hour.toString().padLeft(2, '0')}:$minute';
    }
    final hour = date.hour % 12 == 0 ? 12 : date.hour % 12;
    final period = date.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }
}

enum _Order { monthDayYear, dayMonthYear, yearMonthDay }

const _shortMonths = [
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

const _longMonths = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
