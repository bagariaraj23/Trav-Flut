import type { PrismaClient } from "@prisma/client";

export enum TripStatus {
  UPCOMING = "UPCOMING",
  ONGOING = "ONGOING",
  ENDED = "ENDED",
}

// Encapsulate the transition logic for easier unit testing
export async function updateTripStatuses(
  prisma: PrismaClient,
  now: Date
): Promise<void> {
  await prisma.$transaction([
    prisma.trip.updateMany({
      where: {
        endDate: { lte: now },
        status: { in: [TripStatus.UPCOMING, TripStatus.ONGOING] },
      },
      data: { status: TripStatus.ENDED },
    }),
    prisma.trip.updateMany({
      where: {
        startDate: { lte: now },
        endDate: { gt: now },
        status: TripStatus.UPCOMING,
      },
      data: { status: TripStatus.ONGOING },
    }),
  ]);
}
