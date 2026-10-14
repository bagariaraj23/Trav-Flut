import { TripStatus, TripType } from "@prisma/client";
import { prisma, type PrismaTransactionClient } from "@/lib/prisma";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";

type ScheduleTrip = {
  id: string;
  status: TripStatus;
  startDate: Date;
  endDate: Date | null;
  userId: string;
};

type TripTypeClient = PrismaTransactionClient | typeof prisma;

/**
 * Absolute UTC comparison. Null endDate means the trip stays open until a manual end.
 * A due end wins over a due start so a fully elapsed window becomes ENDED.
 */
export function nextTripStatus(
  trip: { status: TripStatus; startDate: Date; endDate: Date | null },
  now: Date
): TripStatus | null {
  if (trip.status === TripStatus.ENDED) return null;

  if (
    trip.endDate &&
    trip.endDate.getTime() <= now.getTime() &&
    (trip.status === TripStatus.UPCOMING || trip.status === TripStatus.ONGOING)
  ) {
    return TripStatus.ENDED;
  }

  if (
    trip.status === TripStatus.UPCOMING &&
    trip.startDate.getTime() <= now.getTime() &&
    (trip.endDate == null || trip.endDate.getTime() > now.getTime())
  ) {
    return TripStatus.ONGOING;
  }

  return null;
}

/** Solo until a second person is on the trip, then Group. Never Couple or Family. */
export function resolveAutoTripType(participantCount: number): TripType {
  return participantCount >= 2 ? TripType.GROUP : TripType.SOLO;
}

export async function applyAutoTripType(
  db: TripTypeClient,
  tripId: string
): Promise<void> {
  const trip = await db.trip.findUnique({
    where: { id: tripId },
    select: { typeSetByUser: true, participantCount: true },
  });
  if (!trip || trip.typeSetByUser) return;

  await db.trip.update({
    where: { id: tripId },
    data: { type: resolveAutoTripType(trip.participantCount) },
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
      userId: true,
    },
  });
  if (!trip || trip.status === TripStatus.ENDED) return;
  await syncTripRecords([trip]);
}
