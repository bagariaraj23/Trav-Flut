import type { PrismaClient } from "@prisma/client";
import { buildMemberFinalDraft, type DraftTrip } from "./memberFinalDraft";
import { scheduledEndInstant } from "./tripEnd";

export enum TripStatus {
  UPCOMING = "UPCOMING",
  ONGOING = "ONGOING",
  ENDED = "ENDED",
}

// The scheduler cannot import the API service. The personal draft itself lives in
// memberFinalDraft.ts, which the API finalizer imports, so both endings write the same unpublished draft.

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
            media: true,
            threadEntries: {
              include: {
                media: true,
                place: true,
                taggedUsers: { select: { taggedUserId: true } },
              },
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
          select: { userId: true, generationStatus: true, isPublished: true },
        });
        const kept = new Set(
          existingPosts
            .filter(
              (post) => post.isPublished || post.generationStatus !== "DRAFT"
            )
            .map((post) => post.userId)
        );
        const replaceDraft = new Set(
          existingPosts
            .filter(
              (post) => !post.isPublished && post.generationStatus === "DRAFT"
            )
            .map((post) => post.userId)
        );
        const draftTrip: DraftTrip = {
          title: tripData.title,
          startDate: tripData.startDate,
          endDate: tripData.endDate,
          destinations: tripData.destinations ?? [],
          mood: tripData.mood,
          entries: (tripData.threadEntries ?? []).map((entry) => ({
            authorId: entry.authorId,
            contentText: entry.contentText,
            createdAt: entry.createdAt,
            locationName: entry.locationName,
            media: entry.media
              ? {
                  url: entry.media.url,
                  type: entry.media.type,
                  processingStatus: entry.media.processingStatus,
                  uploadedById: entry.media.uploadedById,
                }
              : null,
            taggedUserIds: (entry.taggedUsers ?? []).map(
              (tag) => tag.taggedUserId
            ),
            placeName: entry.place?.name ?? null,
          })),
          uploadedMedia: (tripData.media ?? []).map((media) => ({
            url: media.url,
            type: media.type,
            processingStatus: media.processingStatus,
            uploadedById: media.uploadedById,
          })),
        };

        for (const memberId of memberIds) {
          if (kept.has(memberId)) continue;
          const draft = buildMemberFinalDraft(draftTrip, memberId);
          const data = {
            summaryText: draft.summaryText,
            curatedMedia: draft.curatedMedia,
            caption: draft.caption,
            coverMediaUrl: draft.coverMediaUrl,
            generationStatus: draft.generationStatus,
          };
          if (replaceDraft.has(memberId)) {
            await tx.tripFinalPost.update({
              where: { tripId_userId: { tripId: trip.id, userId: memberId } },
              data,
            });
            continue;
          }
          await tx.tripFinalPost.create({
            data: {
              tripId: trip.id,
              userId: memberId,
              ...data,
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
