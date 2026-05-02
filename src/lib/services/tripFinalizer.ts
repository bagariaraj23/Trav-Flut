import { prisma, type PrismaTransactionClient } from "@/lib/prisma";
import {
  GenerationStatus,
  MediaProcessingStatus,
  MediaType,
  Trip,
  TripFinalPost,
} from "@prisma/client";
import {
  AuthorizationError,
  ConflictError,
  NotFoundError,
  ValidationError,
} from "@/lib/errors";

const MS_IN_DAY = 1000 * 60 * 60 * 24;
const MIN_SUMMARY_LENGTH = 50;
const MIN_MEDIA_COUNT = 1;
const MAX_MEDIA_COUNT = 10;

type FinalPostUpdates = {
  summaryText?: string;
  curatedMedia?: string[];
  caption?: string | null;
  coverMediaUrl?: string | null;
};

export class TripFinalizerService {
  /**
   * Generate final post for a trip. Can work with or without a transaction client.
   * @param tripId - The trip ID
   * @param userId - The user ID (optional for scheduler/system operations)
   * @param tx - Optional transaction client for atomic operations (same type as prisma for extended client compatibility)
   */
  static async generateFinalPost(
    tripId: string,
    userId?: string,
    tx?: PrismaTransactionClient | typeof prisma
  ) {
    const db = tx || prisma;

    // Check if final post already exists (inside transaction if provided)
    const existing = await db.tripFinalPost.findUnique({
      where: { tripId },
      select: {
        id: true,
        tripId: true,
        summaryText: true,
        curatedMedia: true,
        caption: true,
        coverMediaUrl: true,
        generationStatus: true,
        isPublished: true,
        publishedAt: true,
        createdAt: true,
        updatedAt: true,
      },
    });
    if (existing) {
      return existing;
    }

    // Fetch trip with all necessary data (inside transaction if provided)
    const trip = await db.trip.findUnique({
      where: { id: tripId },
      include: {
        threadEntries: {
          include: {
            media: true,
            place: true,
          },
          orderBy: { createdAt: "asc" },
        },
        media: true,
      },
    });

    if (!trip) {
      throw new NotFoundError("Trip not found");
    }

    // Only check authorization if userId is provided (skip for scheduler)
    if (userId && trip.userId !== userId) {
      throw new AuthorizationError("Only the trip owner can finalize the trip");
    }

    const typedTrip = trip as TripForFinalizer;

    const summaryText = buildSummary(typedTrip);
    const curatedMedia = selectCuratedMedia(typedTrip);
    const coverMediaUrl =
      curatedMedia[0] ?? typedTrip.media.find((m) => !!m.url)?.url ?? null;
    const caption = generateDefaultCaption(typedTrip);

    // Create final post (inside transaction if provided)
    return db.tripFinalPost.create({
      data: {
        tripId,
        summaryText,
        curatedMedia,
        caption,
        coverMediaUrl,
        generationStatus: GenerationStatus.READY,
      },
      select: {
        id: true,
        tripId: true,
        summaryText: true,
        curatedMedia: true,
        caption: true,
        coverMediaUrl: true,
        generationStatus: true,
        isPublished: true,
        publishedAt: true,
        createdAt: true,
        updatedAt: true,
      },
    });
  }

  static async getFinalPost(tripId: string) {
    const finalPost = await prisma.tripFinalPost.findUnique({
      where: { tripId },
      select: {
        id: true,
        tripId: true,
        summaryText: true,
        curatedMedia: true,
        caption: true,
        coverMediaUrl: true,
        generationStatus: true,
        isPublished: true,
        publishedAt: true,
        createdAt: true,
        updatedAt: true,
      },
    });

    if (!finalPost) {
      throw new NotFoundError("Final post not found");
    }

    return finalPost;
  }

  static async updateFinalPost(tripId: string, updates: FinalPostUpdates) {
    // Wrap in transaction to prevent race conditions
    return await prisma.$transaction(async (tx) => {
      // Check if final post exists and is not published (inside transaction)
      const finalPost = await tx.tripFinalPost.findUnique({
        where: { tripId },
        select: {
          id: true,
          isPublished: true,
        },
      });

      if (!finalPost) {
        throw new NotFoundError("Final post not found");
      }

      if (finalPost.isPublished) {
        throw new ConflictError("Published posts cannot be edited");
      }

      const data: FinalPostUpdates = {};

      if (typeof updates.summaryText === "string") {
        if (!updates.summaryText.trim()) {
          throw new ValidationError("Summary text cannot be empty");
        }
        data.summaryText = updates.summaryText.trim();
      }

      if (Array.isArray(updates.curatedMedia)) {
        data.curatedMedia = sanitizeMedia(updates.curatedMedia);
        if (data.curatedMedia.length > MAX_MEDIA_COUNT) {
          data.curatedMedia = data.curatedMedia.slice(0, MAX_MEDIA_COUNT);
        }
        if (!data.curatedMedia.length && data.summaryText?.length) {
          // allow text-only drafts
        }
      }

      if (updates.caption !== undefined) {
        data.caption = updates.caption?.trim() || null;
      }

      if (updates.coverMediaUrl !== undefined) {
        data.coverMediaUrl = updates.coverMediaUrl || null;
      } else if (data.curatedMedia && data.curatedMedia.length > 0) {
        data.coverMediaUrl = data.curatedMedia[0];
      }

      // Update final post (inside transaction)
      return tx.tripFinalPost.update({
        where: { tripId },
        data: {
          ...data,
          generationStatus: GenerationStatus.READY,
          updatedAt: new Date(),
        },
        select: {
          id: true,
          tripId: true,
          summaryText: true,
          curatedMedia: true,
          caption: true,
          coverMediaUrl: true,
          generationStatus: true,
          isPublished: true,
          publishedAt: true,
          createdAt: true,
          updatedAt: true,
        },
      });
    });
  }

  static async publishFinalPost(tripId: string, userId: string) {
    // Wrap in transaction to prevent race conditions
    return await prisma.$transaction(async (tx) => {
      // Fetch trip and final post (inside transaction)
      const trip = await tx.trip.findUnique({
        where: { id: tripId },
        select: {
          id: true,
          userId: true,
          finalPost: {
            select: {
              id: true,
              isPublished: true,
              summaryText: true,
              curatedMedia: true,
              coverMediaUrl: true,
            },
          },
        },
      });

      if (!trip) {
        throw new NotFoundError("Trip not found");
      }

      if (trip.userId !== userId) {
        throw new AuthorizationError("Only the trip owner can publish");
      }

      if (!trip.finalPost) {
        throw new NotFoundError("Final post not found");
      }

      if (trip.finalPost.isPublished) {
        throw new ConflictError("Final post has already been published");
      }

      if (!trip.finalPost.summaryText?.trim()) {
        throw new ValidationError("Summary text is required to publish");
      }

      if (trip.finalPost.summaryText.trim().length < MIN_SUMMARY_LENGTH) {
        throw new ValidationError(
          `Summary must be at least ${MIN_SUMMARY_LENGTH} characters`
        );
      }

      if (
        (!trip.finalPost.curatedMedia ||
          trip.finalPost.curatedMedia.length < MIN_MEDIA_COUNT) &&
        !trip.finalPost.coverMediaUrl
      ) {
        throw new ValidationError(
          `Select at least ${MIN_MEDIA_COUNT} media item before publishing`
        );
      }

      // Update final post (inside transaction)
      return tx.tripFinalPost.update({
        where: { tripId },
        data: {
          isPublished: true,
          publishedAt: new Date(),
          generationStatus: GenerationStatus.PUBLISHED,
          updatedAt: new Date(),
        },
        select: {
          id: true,
          tripId: true,
          summaryText: true,
          curatedMedia: true,
          caption: true,
          coverMediaUrl: true,
          generationStatus: true,
          isPublished: true,
          publishedAt: true,
          createdAt: true,
          updatedAt: true,
        },
      });
    });
  }
}

function buildSummary(trip: TripForFinalizer) {
  const durationDays = Math.max(
    1,
    Math.round(
      (trip.endDate.getTime() - trip.startDate.getTime()) / MS_IN_DAY
    ) + 1
  );
  const destinations = trip.destinations ?? [];
  const locationSet = new Set<string>();

  trip.threadEntries.forEach((entry) => {
    if (entry.place?.name) {
      locationSet.add(entry.place.name);
    } else if (entry.locationName) {
      locationSet.add(entry.locationName);
    }
  });

  const highlightedLocations = Array.from(locationSet).slice(0, 3);
  const textEntries = trip.threadEntries
    .filter((entry) => entry.contentText)
    .sort(
      (a, b) =>
        (b.contentText?.length ?? 0) - (a.contentText?.length ?? 0)
    )
    .slice(0, 2)
    .map((entry) => `“${truncate(entry.contentText!, 160)}”`);

  const tripTitle = trip.title?.trim() ?? "";
  const destinationLabel =
    destinations.length > 1
      ? `${destinations.length} places`
      : destinations.length === 1
        ? destinations[0]!
        : tripTitle || "your trip";

  const opening =
    destinations.length === 0
        ? `${tripTitle || "your trip"} was a ${durationDays}-day adventure.`
        : `${tripTitle || destinationLabel} was a ${durationDays}-day adventure through ${destinationLabel}.`;

  const summaryParts = [
    opening,
    highlightedLocations.length
      ? `Highlights included ${highlightedLocations.join(", ")}.`
      : undefined,
    // entryCount
    //   ? `We shared ${entryCount} moments and saved ${mediaCount} favorite photos along the way.`
    //   : undefined,
    textEntries.join(" "),
  ].filter(Boolean);

  return summaryParts.join(" ").trim();
}

function selectCuratedMedia(trip: TripForFinalizer) {
  const mediaEntries = trip.threadEntries
    .filter(
      (entry) =>
        entry.media &&
        entry.media.type === MediaType.IMAGE &&
        entry.media.processingStatus !== MediaProcessingStatus.FAILED &&
        !!entry.media.url
    )
    .map((entry) => ({
      url: entry.media!.url as string,
      createdAt: entry.createdAt,
    }));

  if (!mediaEntries.length) {
    return [];
  }

  const sorted = mediaEntries.sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime()
  );
  const selected: string[] = [];
  const perDay = new Set<string>();
  const extras: string[] = [];

  for (const item of sorted) {
    const dayKey = item.createdAt.toISOString().substring(0, 10);
    if (
      !perDay.has(dayKey) &&
      selected.length < MAX_MEDIA_COUNT
    ) {
      selected.push(item.url);
      perDay.add(dayKey);
    } else {
      extras.push(item.url);
    }
  }

  for (const url of extras) {
    if (selected.length >= MAX_MEDIA_COUNT) {
      break;
    }
    selected.push(url);
  }

  return selected;
}

function generateDefaultCaption(trip: TripForFinalizer) {
  const primaryDestination =
    trip.destinations[0]?.trim() ||
    trip.title?.trim() ||
    "your trip";
  const mood = trip.mood ? `#${trip.mood.toLowerCase()}` : "";
  return [`#${sanitizeTag(primaryDestination)}`, mood]
    .filter(Boolean)
    .join(" ");
}

function sanitizeTag(input: string) {
  return input
    .trim()
    .replace(/\s+/g, "")
    .replace(/[^a-zA-Z0-9]/g, "");
}

function truncate(value: string, limit: number) {
  if (value.length <= limit) {
    return value;
  }
  return `${value.slice(0, limit - 1)}…`;
}

function sanitizeMedia(urls: string[]) {
  return urls
    .map((url) => url?.trim())
    .filter((url): url is string => !!url);
}

type TripForFinalizer = Trip & {
  threadEntries: ThreadEntryWithExtras[];
  media: {
    url: string | null;
  }[];
};

type ThreadEntryWithExtras = {
  id: string;
  contentText: string | null;
  createdAt: Date;
  mediaId: string | null;
  locationName: string | null;
  media: {
    url: string | null;
    type: MediaType;
    processingStatus: MediaProcessingStatus;
  } | null;
  place: {
    name: string;
  } | null;
};

