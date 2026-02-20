import { prisma } from "@/lib/prisma";
import {
  GenerationStatus,
  MediaProcessingStatus,
  MediaType,
  Trip,
  PrismaClient,
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
   * @param tx - Optional transaction client for atomic operations
   */
  static async generateFinalPost(
    tripId: string,
    userId: string,
    tx?: Omit<
      PrismaClient,
      | "$connect"
      | "$disconnect"
      | "$on"
      | "$transaction"
      | "$use"
      | "$extends"
    >
  ) {
    const db = tx || prisma;

    await this.ensureParticipant(db, tripId, userId);

    // Check if final post already exists (inside transaction if provided)
    const existing = await db.tripFinalPost.findUnique({
      where: {
        tripId_userId: {
          tripId,
          userId,
        },
      },
      select: {
        id: true,
        tripId: true,
        userId: true,
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
            taggedUsers: true,
          },
          orderBy: { createdAt: "asc" },
        },
        media: true,
      },
    });

    if (!trip) {
      throw new NotFoundError("Trip not found");
    }

    const typedTrip = trip as TripForFinalizer;

    const summaryText = buildSummary(typedTrip, userId);
    const curatedMedia = selectCuratedMedia(typedTrip, userId);
    const coverMediaUrl =
      curatedMedia[0] ?? typedTrip.media.find((m) => !!m.url)?.url ?? null;
    const caption = generateDefaultCaption(typedTrip, userId);

    // Create final post (inside transaction if provided)
    return db.tripFinalPost.create({
      data: {
        tripId,
        userId,
        summaryText,
        curatedMedia,
        caption,
        coverMediaUrl,
        generationStatus: GenerationStatus.READY,
      },
      select: {
        id: true,
        tripId: true,
        userId: true,
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

  static async getFinalPost(tripId: string, userId: string) {
    await this.ensureParticipant(prisma, tripId, userId);

    const finalPost = await prisma.tripFinalPost.findUnique({
      where: {
        tripId_userId: {
          tripId,
          userId,
        },
      },
      select: {
        id: true,
        tripId: true,
        userId: true,
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

  static async updateFinalPost(
    tripId: string,
    userId: string,
    updates: FinalPostUpdates
  ) {
    // Wrap in transaction to prevent race conditions
    return await prisma.$transaction(async (tx) => {
      await this.ensureParticipant(tx, tripId, userId);

      // Check if final post exists and is not published (inside transaction)
      const finalPost = await tx.tripFinalPost.findUnique({
        where: {
          tripId_userId: {
            tripId,
            userId,
          },
        },
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
        where: {
          tripId_userId: {
            tripId,
            userId,
          },
        },
        data: {
          ...data,
          generationStatus: GenerationStatus.READY,
          updatedAt: new Date(),
        },
        select: {
          id: true,
          tripId: true,
          userId: true,
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
      await this.ensureParticipant(tx, tripId, userId);

      const finalPost = await tx.tripFinalPost.findUnique({
        where: {
          tripId_userId: {
            tripId,
            userId,
          },
        },
        select: {
          id: true,
          isPublished: true,
          summaryText: true,
          curatedMedia: true,
          coverMediaUrl: true,
        },
      });

      if (!finalPost) {
        throw new NotFoundError("Final post not found");
      }

      if (finalPost.isPublished) {
        throw new ConflictError("Final post has already been published");
      }

      if (!finalPost.summaryText?.trim()) {
        throw new ValidationError("Summary text is required to publish");
      }

      if (finalPost.summaryText.trim().length < MIN_SUMMARY_LENGTH) {
        throw new ValidationError(
          `Summary must be at least ${MIN_SUMMARY_LENGTH} characters`
        );
      }

      if (
        (!finalPost.curatedMedia ||
          finalPost.curatedMedia.length < MIN_MEDIA_COUNT) &&
        !finalPost.coverMediaUrl
      ) {
        throw new ValidationError(
          `Select at least ${MIN_MEDIA_COUNT} media item before publishing`
        );
      }

      // Update final post (inside transaction)
      return tx.tripFinalPost.update({
        where: {
          tripId_userId: {
            tripId,
            userId,
          },
        },
        data: {
          isPublished: true,
          publishedAt: new Date(),
          generationStatus: GenerationStatus.PUBLISHED,
          updatedAt: new Date(),
        },
        select: {
          id: true,
          tripId: true,
          userId: true,
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

  private static async ensureParticipant(
    db: Omit<
      PrismaClient,
      | "$connect"
      | "$disconnect"
      | "$on"
      | "$transaction"
      | "$use"
      | "$extends"
    >,
    tripId: string,
    userId: string
  ) {
    const trip = await db.trip.findUnique({
      where: { id: tripId },
      select: { id: true, userId: true },
    });

    if (!trip) {
      throw new NotFoundError("Trip not found");
    }

    if (trip.userId === userId) {
      return;
    }

    const participant = await db.tripParticipant.findUnique({
      where: {
        tripId_userId: {
          tripId,
          userId,
        },
      },
      select: { id: true },
    });

    if (!participant) {
      throw new AuthorizationError("Only trip participants can access final post");
    }
  }
}

function buildSummary(trip: TripForFinalizer, userId: string) {
  const durationDays = Math.max(
    1,
    Math.round(
      (trip.endDate.getTime() - trip.startDate.getTime()) / MS_IN_DAY
    ) + 1
  );
  const destinations = trip.destinations ?? [];
  const locationSet = new Set<string>();

  const prioritizedEntries = rankEntriesForUser(trip.threadEntries, userId);

  prioritizedEntries.forEach((entry) => {
    if (entry.place?.name) {
      locationSet.add(entry.place.name);
    } else if (entry.locationName) {
      locationSet.add(entry.locationName);
    }
  });

  const highlightedLocations = Array.from(locationSet).slice(0, 3);
  const textEntries = prioritizedEntries
    .filter((entry) => entry.contentText)
    .sort(
      (a, b) =>
        (b.contentText?.length ?? 0) - (a.contentText?.length ?? 0)
    )
    .slice(0, 2)
    .map((entry) => `“${truncate(entry.contentText!, 160)}”`);

  const destinationLabel =
    destinations.length > 1
      ? `${destinations.length} places`
      : destinations[0] ?? "the road";

  const summaryParts = [
    `${trip.title} was a ${durationDays}-day adventure through ${destinationLabel}.`,
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

function selectCuratedMedia(trip: TripForFinalizer, userId: string) {
  const mediaEntries = rankEntriesForUser(trip.threadEntries, userId)
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

function generateDefaultCaption(trip: TripForFinalizer, _userId: string) {
  const primaryDestination = trip.destinations[0] ?? trip.title;
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
  authorId: string;
  contentText: string | null;
  createdAt: Date;
  mediaId: string | null;
  locationName: string | null;
  taggedUsers?: {
    taggedUserId: string;
  }[];
  media: {
    url: string | null;
    type: MediaType;
    processingStatus: MediaProcessingStatus;
  } | null;
  place: {
    name: string;
  } | null;
};

function rankEntriesForUser(entries: ThreadEntryWithExtras[], userId: string) {
  const ownEntries = entries.filter((entry) => entry.authorId === userId);
  const taggedEntries = entries.filter(
    (entry) =>
      entry.authorId !== userId &&
      (entry.taggedUsers || []).some((tag) => tag.taggedUserId === userId)
  );
  const remainingEntries = entries.filter(
    (entry) =>
      entry.authorId !== userId &&
      !(entry.taggedUsers || []).some((tag) => tag.taggedUserId === userId)
  );

  return [...ownEntries, ...taggedEntries, ...remainingEntries];
}
