import type { PrismaClient } from "@prisma/client";

export enum TripStatus {
  UPCOMING = "UPCOMING",
  ONGOING = "ONGOING",
  ENDED = "ENDED",
}

// Helper function to create final post for a trip
// This matches the logic used when a trip is ended manually via /api/trips/[id]/end
async function createFinalPostForTrip(
  prisma: PrismaClient,
  tripId: string,
  destinations: string[]
): Promise<void> {
  // Check if final post already exists
  const existingFinalPost = await prisma.tripFinalPost.findUnique({
    where: { tripId },
  });

  if (existingFinalPost) {
    // Final post already exists, skip creation
    return;
  }

  // Get trip with thread entries (same structure as manual end trip)
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    include: {
      threadEntries: {
        where: {
          type: "MEDIA",
          mediaId: { not: null },
        },
        include: {
          media: {
            select: {
              id: true,
              url: true,
            },
          },
        },
        orderBy: { createdAt: "asc" },
      },
    },
  });

  if (!trip) {
    // Trip not found, skip
    return;
  }

  // Get all thread entries to properly count TEXT and LOCATION entries
  // (Manual end trip filters trip.threadEntries but that only has MEDIA, so we fetch all)
  const allThreadEntries = await prisma.tripThreadEntry.findMany({
    where: { tripId },
    orderBy: { createdAt: "asc" },
  });

  // Filter entries by type (same logic as manual end trip)
  const textEntries = allThreadEntries.filter(
    (entry) => entry.type === "TEXT" && entry.contentText
  );
  const mediaEntries = trip.threadEntries.filter(
    (entry) => entry.type === "MEDIA" && entry.mediaId
  );
  const locationEntries = allThreadEntries.filter(
    (entry) => entry.type === "LOCATION" && entry.locationName
  );

  // Generate summary text (same logic as manual end trip)
  let summaryText = `Amazing trip to ${destinations.join(", ")}! `;

  if (locationEntries.length > 0) {
    summaryText += `Visited ${locationEntries.length} amazing places. `;
  }

  if (textEntries.length > 0) {
    summaryText += `Shared ${textEntries.length} memorable moments. `;
  }

  if (mediaEntries.length > 0) {
    summaryText += `Captured ${mediaEntries.length} beautiful memories.`;
  }

  // Get curated media (first 6 media entries) - same as manual end trip
  const curatedMedia = mediaEntries
    .slice(0, 6)
    .map((entry) => entry.media?.url)
    .filter((url): url is string => Boolean(url));

  // Create final post (same as manual end trip)
  await prisma.tripFinalPost.create({
    data: {
      tripId,
      summaryText,
      curatedMedia,
      caption: `My trip to ${destinations.join(", ")} was incredible! 🌟`,
    },
  });
}

// Encapsulate the transition logic for easier unit testing
export async function updateTripStatuses(
  prisma: PrismaClient,
  now: Date
): Promise<void> {
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
        // If final post already exists, skip
        const existingFinalPost = await tx.tripFinalPost.findUnique({
          where: { tripId: trip.id },
        });
        if (!existingFinalPost) {
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
          let summaryText = `Amazing trip to ${trip.destinations.join(", ")}! `;
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
              caption: `My trip to ${trip.destinations.join(
                ", "
              )} was incredible! 🌟`,
            },
          });
        }
        // Update trip status
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
  await prisma.$transaction(async (tx) => {
    await tx.trip.updateMany({
      where: {
        startDate: { lte: now },
        endDate: { gt: now },
        status: TripStatus.UPCOMING,
      },
      data: { status: TripStatus.ONGOING },
    });
  });
}
