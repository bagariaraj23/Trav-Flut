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
  // First, find trips that will be ended (before updating status)
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

  // Create final posts for trips that will be ended
  // Do this before updating status to ensure we have the trip data
  for (const trip of tripsToEnd) {
    try {
      await createFinalPostForTrip(prisma, trip.id, trip.destinations);
    } catch (error) {
      // Log error but continue with other trips
      console.error(
        `Failed to create final post for trip ${trip.id}:`,
        error instanceof Error ? error.message : String(error)
      );
    }
  }

  // Now update trip statuses in a transaction
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
