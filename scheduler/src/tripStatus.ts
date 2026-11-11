import type { PrismaClient } from "@prisma/client";
import { scheduledEndInstant } from "./tripEnd";

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
 * Trip start/end values are absolute UTC instants (see src/lib/tripSchedule.ts).
 * A midnight end date lasts through 11:59:59.999 PM in scheduleTimezone.
 * A chosen end time ends at that instant.
 * Null endDate is manual-end only. Open-ended trips still start when startDate <= now.
 * Cron "0 * * * *" runs at minute 0 each hour; trip reads apply the same rules
 * so the app does not wait for the next run.
 */
export async function updateTripStatuses(
  prisma: PrismaClient,
  now: Date
): Promise<UpdateTripStatusesResult> {
  const nowIso = now.toISOString();

  const dueTrips = await prisma.trip.findMany({
    where: {
      status: { in: [TripStatus.UPCOMING, TripStatus.ONGOING] },
      OR: [
        { endDate: { lte: now } },
        { status: TripStatus.UPCOMING, startDate: { lte: now } },
      ],
    },
    select: {
      id: true,
      destinations: true,
      title: true,
      status: true,
      startDate: true,
      endDate: true,
      scheduleTimezone: true,
    },
  });

  const tripsToEnd = dueTrips.filter((trip) => {
    if (!trip.endDate) return false;
    const end = scheduledEndInstant(trip.endDate, trip.scheduleTimezone);
    return end.getTime() <= now.getTime();
  });
  const tripsToStart = dueTrips.filter((trip) => {
    if (trip.status !== TripStatus.UPCOMING) return false;
    if (trip.startDate.getTime() > now.getTime()) return false;
    if (!trip.endDate) return true;
    const end = scheduledEndInstant(trip.endDate, trip.scheduleTimezone);
    return end.getTime() > now.getTime();
  });

  // For each trip, atomically: (a) create final post if needed, (b) update status
  for (const trip of tripsToEnd) {
    try {
      await prisma.$transaction(async (tx) => {
        // Personal draft for the owner and each participant. Kept inline so the
        // scheduler build does not import the API service.
        const tripData = await tx.trip.findUnique({
          where: { id: trip.id },
          include: {
            participants: { select: { userId: true } },
            threadEntries: {
              include: { media: true },
              orderBy: { createdAt: "asc" },
            },
          },
        });
        if (!tripData) throw new Error("Trip not found");

        const memberIds = [
          ...new Set([
            tripData.userId,
            ...(tripData.participants ?? []).map(
              (participant) => participant.userId
            ),
          ]),
        ];
        const existingPosts = await tx.tripFinalPost.findMany({
          where: { tripId: trip.id, userId: { in: memberIds } },
          select: { userId: true },
        });
        const alreadyDrafted = new Set(existingPosts.map((post) => post.userId));
        const entries = tripData.threadEntries ?? [];
        const titleTrim = trip.title?.trim() ?? "";
        const destLabel =
          trip.destinations?.length > 0
            ? trip.destinations.join(", ")
            : titleTrim || "your trip";

        for (const memberId of memberIds) {
          if (alreadyDrafted.has(memberId)) continue;
          const ownEntries = entries.filter(
            (entry) =>
              entry.authorId === memberId ||
              entry.media?.uploadedById === memberId
          );
          const textEntries = ownEntries.filter(
            (entry) => entry.type === "TEXT" && entry.contentText
          );
          const mediaEntries = ownEntries.filter(
            (entry) =>
              entry.media?.url &&
              (entry.media.type == null || entry.media.type === "IMAGE")
          );
          const locationEntries = ownEntries.filter(
            (entry) => entry.type === "LOCATION" && entry.locationName
          );
          let summaryText = `Your trip to ${destLabel}! `;
          if (locationEntries.length > 0)
            summaryText += `You visited ${locationEntries.length} places. `;
          if (textEntries.length > 0)
            summaryText += `You shared ${textEntries.length} notes. `;
          if (mediaEntries.length > 0)
            summaryText += `You kept ${mediaEntries.length} of your photos.`;
          else
            summaryText += "Add the photos you took before you publish.";
          const curatedMedia = mediaEntries
            .slice(0, 6)
            .map((entry) => entry.media?.url)
            .filter((url): url is string => Boolean(url));
          await tx.tripFinalPost.create({
            data: {
              tripId: trip.id,
              userId: memberId,
              summaryText,
              curatedMedia,
              caption: `My trip to ${titleTrim || destLabel} was incredible! 🌟`,
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

  const ongoingResult = await prisma.$transaction(async (tx) => {
    return tx.trip.updateMany({
      where: {
        id: { in: tripsToStart.map((trip) => trip.id) },
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
