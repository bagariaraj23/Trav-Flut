import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/utils/date_utils.dart' as trip_dates;
import 'package:tripthread/utils/locale_dates.dart';

/// CLDR puts a narrow no-break space before the day period.
const _gap = '\u202f';

void main() {
  final march20 = DateTime(2026, 3, 20, 18, 30);

  setUpAll(() async {
    await LocaleDates.ensureInitialized();
  });

  tearDown(() {
    LocaleDates.debugLocaleOverride = null;
  });

  Future<void> use(String locale) async {
    LocaleDates.debugLocaleOverride = locale;
  }

  test('India uses day/month and a 12-hour clock', () async {
    await use('en_IN');
    expect(LocaleDates.numericDate(march20), '20/3/2026');
    expect(LocaleDates.monthDay(march20), '20/03');
    expect(LocaleDates.mediumDate(march20), '20 Mar 2026');
    expect(LocaleDates.longDate(march20), '20 March 2026');
    expect(LocaleDates.timeOfDay(march20), '6:30${_gap}pm');
    expect(LocaleDates.mediumDateTime(march20), '20 Mar, 6:30${_gap}pm');
  });

  test('United States uses month/day', () async {
    await use('en_US');
    expect(LocaleDates.numericDate(march20), '3/20/2026');
    expect(LocaleDates.monthDay(march20), '3/20');
    expect(LocaleDates.mediumDate(march20), 'Mar 20, 2026');
    expect(LocaleDates.longDate(march20), 'March 20, 2026');
    expect(LocaleDates.timeOfDay(march20), '6:30${_gap}PM');
    expect(LocaleDates.mediumDateTime(march20), 'Mar 20, 6:30${_gap}PM');
  });

  test('United Kingdom uses day/month and a 24-hour clock', () async {
    await use('en_GB');
    expect(LocaleDates.numericDate(march20), '20/03/2026');
    expect(LocaleDates.monthDay(march20), '20/03');
    expect(LocaleDates.mediumDate(march20), '20 Mar 2026');
    expect(LocaleDates.timeOfDay(march20), '18:30');
    expect(LocaleDates.longDate(march20), '20 March 2026');
  });

  test('Japan and a Japanese region tag lead with the year', () async {
    await use('ja_JP');
    expect(LocaleDates.numericDate(march20), '2026/3/20');
    expect(LocaleDates.mediumDate(march20), '2026年3月20日');
  });

  test('Hindi in India stays day/month', () async {
    await use('hi_IN');
    expect(LocaleDates.numericDate(march20), '20/3/2026');
  });

  test('chat stamps follow the region and yesterday crosses month boundaries', () async {
    final now = DateTime(2026, 3, 1, 15);
    await use('en_IN');
    expect(
      LocaleDates.conversationStamp(DateTime(2026, 3, 1, 9, 5), now: now),
      '9:05${_gap}am',
    );
    expect(
      LocaleDates.conversationStamp(DateTime(2026, 2, 28, 23), now: now),
      'Yesterday',
    );
    expect(
      LocaleDates.conversationStamp(DateTime(2026, 1, 5, 12), now: now),
      '05/01',
    );
    expect(
      LocaleDates.dayHeading(DateTime(2026, 3, 20), now: now),
      '20 March 2026',
    );

    await use('en_US');
    expect(
      LocaleDates.conversationStamp(DateTime(2026, 1, 5, 12), now: now),
      '1/5',
    );
    expect(
      LocaleDates.dayHeading(DateTime(2026, 3, 20), now: now),
      'March 20, 2026',
    );
    expect(
      LocaleDates.dayHeading(DateTime(2026, 3, 1, 8), now: now),
      'Today',
    );
  });

  test('calendar-day helper keeps the stored day and the region order', () async {
    await use('en_US');
    expect(
      trip_dates.DateUtils.formatDateForDisplay(DateTime.utc(2026, 3, 20)),
      'Mar 20, 2026',
    );
    await use('en_IN');
    expect(
      trip_dates.DateUtils.formatDateForDisplay(DateTime.utc(2026, 3, 20)),
      '20 Mar 2026',
    );
  });
}
