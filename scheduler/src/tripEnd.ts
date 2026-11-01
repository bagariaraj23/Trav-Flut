/**
 * Keep in step with scheduledEndInstant in src/lib/tripSchedule.ts.
 * The scheduler compiles with its own rootDir and cannot import the API package.
 */

type WallTime = {
  year: number;
  month: number;
  day: number;
  hour: number;
  minute: number;
  second: number;
};

function validTimeZone(timeZone: string | null | undefined): string | null {
  if (!timeZone) return null;
  try {
    Intl.DateTimeFormat("en-US", { timeZone });
    return timeZone;
  } catch {
    return null;
  }
}

function wallTime(instant: Date, timeZone: string): WallTime {
  const formatted = new Intl.DateTimeFormat("en-US", {
    timeZone,
    hourCycle: "h23",
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    second: "2-digit",
  }).formatToParts(instant);
  const part = (type: Intl.DateTimeFormatPartTypes) =>
    formatted.find((item) => item.type === type)?.value ?? "";
  let hour = Number(part("hour"));
  let year = Number(part("year"));
  let month = Number(part("month"));
  let day = Number(part("day"));
  if (hour === 24) {
    hour = 0;
    const next = new Date(Date.UTC(year, month - 1, day + 1));
    year = next.getUTCFullYear();
    month = next.getUTCMonth() + 1;
    day = next.getUTCDate();
  }
  return {
    year,
    month,
    day,
    hour,
    minute: Number(part("minute")),
    second: Number(part("second")),
  };
}

function zoneOffsetMs(instant: Date, timeZone: string): number {
  const wall = wallTime(instant, timeZone);
  const asUtc = Date.UTC(
    wall.year,
    wall.month - 1,
    wall.day,
    wall.hour,
    wall.minute,
    wall.second
  );
  return asUtc - Math.floor(instant.getTime() / 1000) * 1000;
}

function zonedWallTimeToUtc(
  year: number,
  month: number,
  day: number,
  hour: number,
  minute: number,
  second: number,
  millisecond: number,
  timeZone: string
): Date {
  const utcGuess = Date.UTC(year, month - 1, day, hour, minute, second, millisecond);
  const corrected = utcGuess - zoneOffsetMs(new Date(utcGuess), timeZone);
  const confirmed = utcGuess - zoneOffsetMs(new Date(corrected), timeZone);
  return new Date(confirmed);
}

function isUtcMidnight(instant: Date): boolean {
  return (
    instant.getUTCHours() === 0 &&
    instant.getUTCMinutes() === 0 &&
    instant.getUTCSeconds() === 0 &&
    instant.getUTCMilliseconds() === 0
  );
}

/** 11:59:59.999 PM on the end date in the trip timezone. */
export function scheduledEndInstant(
  endDate: Date,
  scheduleTimezone?: string | null
): Date {
  const zone = validTimeZone(scheduleTimezone);
  if (zone) {
    const day = wallTime(endDate, zone);
    return zonedWallTimeToUtc(day.year, day.month, day.day, 23, 59, 59, 999, zone);
  }
  if (isUtcMidnight(endDate)) {
    return new Date(
      Date.UTC(
        endDate.getUTCFullYear(),
        endDate.getUTCMonth(),
        endDate.getUTCDate(),
        23,
        59,
        59,
        999
      )
    );
  }
  return endDate;
}
