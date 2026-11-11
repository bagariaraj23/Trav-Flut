import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/utils/locale_dates.dart';
import 'package:tripthread/utils/trip_time_format.dart';

const _gap = '\u202f';

void main() {
  const stored = '2026-03-20T13:00:00.000Z';

  ZoneClock ist(DateTime utc) => ZoneClock(
        local: utc.add(const Duration(hours: 5, minutes: 30)),
        label: 'IST',
      );

  ZoneClock eastern(DateTime utc) => ZoneClock(
        local: utc.subtract(const Duration(hours: 5)),
        label: 'ET',
      );

  setUpAll(() async {
    await LocaleDates.ensureInitialized();
  });

  tearDown(() {
    LocaleDates.debugLocaleOverride = null;
  });

  test('18:30 IST is stored as 13:00Z and converts for IST and US Eastern', () {
    LocaleDates.debugLocaleOverride = 'en_IN';
    final instant = DateTime.parse(stored);
    expect(instant.toUtc().toIso8601String(), stored);

    expect(
      formatTripInstant(
        instant,
        scheduleTimezone: 'Asia/Kolkata',
        convert: ist,
      ),
      '20 Mar 2026, 6:30${_gap}pm IST',
    );
    expect(
      formatTripInstant(
        instant,
        scheduleTimezone: 'America/New_York',
        convert: eastern,
      ),
      '20 Mar 2026, 8:00${_gap}am ET',
    );
  });

  test('the same instant uses month/day on an American phone', () {
    LocaleDates.debugLocaleOverride = 'en_US';
    final instant = DateTime.parse(stored);
    expect(
      formatTripInstant(
        instant,
        scheduleTimezone: 'Asia/Kolkata',
        convert: ist,
      ),
      'Mar 20, 2026, 6:30${_gap}PM IST',
    );
    expect(
      formatTripInstant(
        instant,
        scheduleTimezone: 'America/New_York',
        convert: eastern,
      ),
      'Mar 20, 2026, 8:00${_gap}AM ET',
    );
  });

  test('legacy UTC midnights stay date-only and open trips say until you end it', () {
    LocaleDates.debugLocaleOverride = 'en_IN';
    expect(
      formatTripInstant(DateTime.utc(2026, 3, 20)),
      '20 Mar 2026',
    );
    expect(
      formatTripRange(
        DateTime.parse(stored),
        null,
        scheduleTimezone: 'Asia/Kolkata',
        convert: ist,
      ),
      '20 Mar 2026, 6:30${_gap}pm IST · Until you end it',
    );

    LocaleDates.debugLocaleOverride = 'en_US';
    expect(
      formatTripInstant(DateTime.utc(2026, 3, 20)),
      'Mar 20, 2026',
    );
  });

  test('joined dates use the regional numeric order', () {
    final joined = DateTime(2026, 3, 20);
    LocaleDates.debugLocaleOverride = 'en_IN';
    expect(formatLocalDate(joined), '20/3/2026');
    LocaleDates.debugLocaleOverride = 'en_US';
    expect(formatLocalDate(joined), '3/20/2026');
    LocaleDates.debugLocaleOverride = 'en_GB';
    expect(formatLocalDate(joined), '20/03/2026');
  });
}
