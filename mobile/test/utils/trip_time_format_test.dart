import 'package:flutter_test/flutter_test.dart';
import 'package:tripthread/utils/trip_time_format.dart';

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

  test('18:30 IST is stored as 13:00Z and converts for IST and US Eastern', () {
    final instant = DateTime.parse(stored);
    expect(instant.toUtc().toIso8601String(), stored);

    expect(
      formatTripInstant(
        instant,
        scheduleTimezone: 'Asia/Kolkata',
        convert: ist,
      ),
      '20 Mar 2026, 6:30 PM IST',
    );
    expect(
      formatTripInstant(
        instant,
        scheduleTimezone: 'America/New_York',
        convert: eastern,
      ),
      '20 Mar 2026, 8:00 AM ET',
    );
  });

  test('legacy UTC midnights stay date-only and open trips say until you end it', () {
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
      '20 Mar 2026, 6:30 PM IST · Until you end it',
    );
  });
}
