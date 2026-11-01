import { TripStatus, TripType } from "@prisma/client";
import { prisma, type PrismaTransactionClient } from "@/lib/prisma";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";

type ScheduleTrip = {
  id: string;
  status: TripStatus;
  startDate: Date;
  endDate: Date | null;
  scheduleTimezone: string | null;
  userId: string;
};

type TripTypeClient = PrismaTransactionClient | typeof prisma;

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

/**
 * A date with no clock time is midnight and lasts through 11:59:59.999 PM
 * in the trip timezone. A chosen time is kept and the trip ends then.
 * A missing zone keeps a precise instant, except a UTC-midnight date, which
 * lasts through 11:59:59.999 PM UTC of that calendar day.
 */
export function scheduledEndInstant(
  endDate: Date,
  scheduleTimezone?: string | null
): Date {
  const zone = validTimeZone(scheduleTimezone);
  if (zone) {
    const day = wallTime(endDate, zone);
    const dateOnly = day.hour === 0 && day.minute === 0 && day.second === 0;
    if (!dateOnly) return endDate;
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

/** True when the next end is after the current one, using the same midnight rule. */
export function endIsLater(
  currentEnd: Date,
  nextEnd: Date,
  scheduleTimezone?: string | null
): boolean {
  return (
    scheduledEndInstant(nextEnd, scheduleTimezone).getTime() >
    scheduledEndInstant(currentEnd, scheduleTimezone).getTime()
  );
}

/**
 * Null endDate means the trip stays open until a manual end.
 * A midnight end date lasts through 11:59:59.999 PM in the trip timezone.
 * Any other end time is that exact instant.
 * A due end wins over a due start so a fully elapsed window becomes ENDED.
 */
export function nextTripStatus(
  trip: {
    status: TripStatus;
    startDate: Date;
    endDate: Date | null;
    scheduleTimezone?: string | null;
  },
  now: Date
): TripStatus | null {
  if (trip.status === TripStatus.ENDED) return null;

  const end = trip.endDate
    ? scheduledEndInstant(trip.endDate, trip.scheduleTimezone)
    : null;

  if (
    end &&
    end.getTime() <= now.getTime() &&
    (trip.status === TripStatus.UPCOMING || trip.status === TripStatus.ONGOING)
  ) {
    return TripStatus.ENDED;
  }

  if (
    trip.status === TripStatus.UPCOMING &&
    trip.startDate.getTime() <= now.getTime() &&
    (end == null || end.getTime() > now.getTime())
  ) {
    return TripStatus.ONGOING;
  }

  return null;
}

/** Solo until a second person is on the trip, then Group. Never Couple or Family. */
export function resolveAutoTripType(participantCount: number): TripType {
  return participantCount >= 2 ? TripType.GROUP : TripType.SOLO;
}

/**
 * Couple and Family stay only when the user specified them.
 * An unset type follows the headcount: one person is Solo, two or more is Group.
 */
export function resolveTripType(input: {
  participantCount: number;
  typeSetByUser: boolean;
  currentType: TripType | null;
}): TripType | null {
  if (input.typeSetByUser) return input.currentType;
  return resolveAutoTripType(input.participantCount);
}

export async function applyAutoTripType(
  db: TripTypeClient,
  tripId: string
): Promise<void> {
  const trip = await db.trip.findUnique({
    where: { id: tripId },
    select: { type: true, typeSetByUser: true, participantCount: true },
  });
  if (!trip) return;

  const next = resolveTripType(trip);
  if (next == null || next === trip.type) return;

  await db.trip.update({
    where: { id: tripId },
    data: { type: next },
  });
}

async function syncTripRecords(trips: ScheduleTrip[]): Promise<void> {
  const now = new Date();
  for (const trip of trips) {
    const next = nextTripStatus(trip, now);
    if (!next) continue;

    try {
      if (next === TripStatus.ENDED) {
        await prisma.$transaction(async (tx) => {
          await tx.trip.update({
            where: { id: trip.id },
            data: { status: TripStatus.ENDED, updatedAt: now },
          });
          await TripFinalizerService.generateFinalPost(trip.id, trip.userId, tx);
        });
      } else {
        await prisma.trip.updateMany({
          where: { id: trip.id, status: TripStatus.UPCOMING },
          data: { status: TripStatus.ONGOING, updatedAt: now },
        });
      }
    } catch (error) {
      console.error(
        `[WARN] Failed to sync trip ${trip.id} to ${next}:`,
        error instanceof Error ? error.message : String(error)
      );
    }
  }
}

/** Catch scheduler lag for the signed-in user's upcoming and ongoing trips. */
export async function syncViewerTripSchedule(userId: string): Promise<void> {
  const trips = await prisma.trip.findMany({
    where: {
      status: { in: [TripStatus.UPCOMING, TripStatus.ONGOING] },
      OR: [{ userId }, { participants: { some: { userId } } }],
    },
    select: {
      id: true,
      status: true,
      startDate: true,
      endDate: true,
      scheduleTimezone: true,
      userId: true,
    },
  });
  await syncTripRecords(trips);
}

export async function syncTripById(tripId: string): Promise<void> {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: {
      id: true,
      status: true,
      startDate: true,
      endDate: true,
      scheduleTimezone: true,
      userId: true,
    },
  });
  if (!trip || trip.status === TripStatus.ENDED) return;
  await syncTripRecords([trip]);
}
