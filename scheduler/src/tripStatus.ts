import type { PrismaClient } from "@prisma/client";

export enum TripStatus {
  UPCOMING = "UPCOMING",
  ONGOING = "ONGOING",
  ENDED = "ENDED",
}

// Note: The scheduler runs as a separate service with its own TypeScript compilation.
// We cannot import from the main app's source code due to rootDir constraints.
// The inline implementation below matches the logic from TripFinalizerService
// to ensure consistency. If the service logic changes, this should be updated accordingly.

/** Result of a run for logging */
export type UpdateTripStatusesResult = {
  nowIso: string;
  endedCount: number;
  ongoingCount: number;
};

/**
 * Trip start/end dates are stored and compared in UTC (see app trip creation).
 * The scheduler should run at or after 00:00 UTC on the trip's start date for
 * UPCOMING → ONGOING. Cron "0 * * * *" runs at minute 0 each hour (UTC on Railway).
 */
export async function updateTripStatuses(
  prisma: PrismaClient,
  now: Date
): Promise<UpdateTripStatusesResult> {
  const nowIso = now.toISOString();

  // Find trips that will be ended
  const tripsToEnd = await prisma.trip.findMany({
    where: {
      endDate: { lte: now },
      status: { in: [TripStatus.UPCOMING, TripStatus.ONGOING] },
    },
    select: {
      id: true,
      destinations: true,
    },
  });

  // For each trip, atomically: (a) create final post if needed, (b) update status
  for (const trip of tripsToEnd) {
    try {
      await prisma.$transaction(async (tx) => {
        // Check if final post already exists (inside transaction)
        const existingFinalPost = await tx.tripFinalPost.findUnique({
          where: { tripId: trip.id },
        });

        if (!existingFinalPost) {
          // Generate final post using inline implementation
          // This matches TripFinalizerService.generateFinalPost logic for consistency
          // Fetch full trip with thread entries for summary (inside tx)
          const tripData = await tx.trip.findUnique({
            where: { id: trip.id },
            include: {
              threadEntries: {
                where: { type: "MEDIA", mediaId: { not: null } },
                include: { media: true },
                orderBy: { createdAt: "asc" },
              },
            },
          });
          if (!tripData) throw new Error("Trip not found");

          // Fetch all thread entries for full summary
          const allThreadEntries = await tx.tripThreadEntry.findMany({
            where: { tripId: trip.id },
            orderBy: { createdAt: "asc" },
          });
          const textEntries = allThreadEntries.filter(
            (entry) => entry.type === "TEXT" && entry.contentText
          );
          const mediaEntries = (tripData.threadEntries || []).filter(
            (entry) => entry.type === "MEDIA" && entry.mediaId
          );
          const locationEntries = allThreadEntries.filter(
            (entry) => entry.type === "LOCATION" && entry.locationName
          );
          const destLabel =
            trip.destinations?.length > 0
              ? trip.destinations.join(", ")
              : "your trip";
          let summaryText = `Amazing trip to ${destLabel}! `;
          if (locationEntries.length > 0)
            summaryText += `Visited ${locationEntries.length} amazing places. `;
          if (textEntries.length > 0)
            summaryText += `Shared ${textEntries.length} memorable moments. `;
          if (mediaEntries.length > 0)
            summaryText += `Captured ${mediaEntries.length} beautiful memories.`;
          const curatedMedia = mediaEntries
            .slice(0, 6)
            .map((entry) => entry.media?.url)
            .filter((url): url is string => Boolean(url));
          await tx.tripFinalPost.create({
            data: {
              tripId: trip.id,
              summaryText,
              curatedMedia,
              caption: `My trip to ${destLabel} was incredible! 🌟`,
            },
          });
        }

        // Update trip status (inside transaction)
        await tx.trip.update({
          where: { id: trip.id },
          data: { status: TripStatus.ENDED },
        });
      });
    } catch (error) {
      console.error(
        `Failed to end trip ${trip.id}:`,
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  // Atomically update ongoing trips in one go (safe, read to write, not used for ending)
  const ongoingResult = await prisma.$transaction(async (tx) => {
    return tx.trip.updateMany({
      where: {
        startDate: { lte: now },
        endDate: { gt: now },
        status: TripStatus.UPCOMING,
      },
      data: { status: TripStatus.ONGOING },
    });
  });

  return {
    nowIso,
    endedCount: tripsToEnd.length,
    ongoingCount: ongoingResult.count,
  };
}
