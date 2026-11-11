import { prisma, type PrismaTransactionClient } from "@/lib/prisma";
import {
  EntityType,
  GenerationStatus,
  MediaProcessingStatus,
  MediaType,
  Trip,
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

const finalPostSelect = {
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
} as const;

type FinalPostUpdates = {
  summaryText?: string;
  curatedMedia?: string[];
  caption?: string | null;
  coverMediaUrl?: string | null;
};

type DbClient = PrismaTransactionClient | typeof prisma;

export class TripFinalizerService {
  /**
   * Draft a personal final post for one member.
   * Photos come from media that member uploaded or posted. Calling again returns the existing draft.
   */
  static async generateFinalPost(
    tripId: string,
    userId: string,
    tx?: DbClient
  ) {
    const db = tx || prisma;
    await this.assertCanAuthor(db, tripId, userId);

    const existing = await db.tripFinalPost.findUnique({
      where: { tripId_userId: { tripId, userId } },
      select: finalPostSelect,
    });
    if (existing) {
      return existing;
    }

    const trip = await db.trip.findUnique({
      where: { id: tripId },
      include: {
        threadEntries: {
          include: {
            media: true,
            place: true,
            taggedUsers: { select: { taggedUserId: true } },
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
    const coverMediaUrl = curatedMedia[0] ?? null;
    const caption = generateDefaultCaption(typedTrip, userId);

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
      select: finalPostSelect,
    });
  }

  /** Draft a personal post for the owner and every current participant. */
  static async generateFinalPostsForMembers(tripId: string, tx?: DbClient) {
    const db = tx || prisma;
    const trip = await db.trip.findUnique({
      where: { id: tripId },
      select: {
        userId: true,
        participants: { select: { userId: true } },
      },
    });

    if (!trip) {
      throw new NotFoundError("Trip not found");
    }

    const memberIds = [
      ...new Set([
        trip.userId,
        ...trip.participants.map((participant) => participant.userId),
      ]),
    ];
    const posts = [];
    for (const memberId of memberIds) {
      posts.push(await this.generateFinalPost(tripId, memberId, db));
    }
    return posts;
  }

  static async getFinalPost(tripId: string, userId: string) {
    await this.assertCanAuthor(prisma, tripId, userId);

    const finalPost = await prisma.tripFinalPost.findUnique({
      where: { tripId_userId: { tripId, userId } },
      select: finalPostSelect,
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
    return await prisma.$transaction(async (tx) => {
      await this.assertCanAuthor(tx, tripId, userId);

      const finalPost = await tx.tripFinalPost.findUnique({
        where: { tripId_userId: { tripId, userId } },
        select: {
          id: true,
          isPublished: true,
          curatedMedia: true,
          coverMediaUrl: true,
        },
      });

      if (!finalPost) {
        throw new NotFoundError("Final post not found");
      }

      const wasPublished = finalPost.isPublished;
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
      }

      if (updates.caption !== undefined) {
        data.caption = updates.caption?.trim() || null;
      }

      if (updates.coverMediaUrl !== undefined) {
        data.coverMediaUrl = updates.coverMediaUrl || null;
      } else if (data.curatedMedia && data.curatedMedia.length > 0) {
        data.coverMediaUrl = data.curatedMedia[0];
      }

      return tx.tripFinalPost.update({
        where: { tripId_userId: { tripId, userId } },
        data: {
          ...data,
          generationStatus: wasPublished
            ? GenerationStatus.PUBLISHED
            : GenerationStatus.READY,
          updatedAt: new Date(),
        },
        select: finalPostSelect,
      });
    });
  }

  static async publishFinalPost(tripId: string, userId: string) {
    return await prisma.$transaction(async (tx) => {
      await this.assertCanAuthor(tx, tripId, userId);

      const finalPost = await tx.tripFinalPost.findUnique({
        where: { tripId_userId: { tripId, userId } },
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
          `Select at least ${MIN_MEDIA_COUNT} photo before publishing`
        );
      }

      return tx.tripFinalPost.update({
        where: { tripId_userId: { tripId, userId } },
        data: {
          isPublished: true,
          publishedAt: new Date(),
          generationStatus: GenerationStatus.PUBLISHED,
          updatedAt: new Date(),
        },
        select: finalPostSelect,
      });
    });
  }

  /** The author removes their own post and its likes, comments, shares, and notifications. */
  static async deleteFinalPost(tripId: string, userId: string) {
    await prisma.$transaction(async (tx) => {
      await this.assertCanAuthor(tx, tripId, userId);

      const finalPost = await tx.tripFinalPost.findUnique({
        where: { tripId_userId: { tripId, userId } },
        select: { id: true },
      });

      if (!finalPost) {
        throw new NotFoundError("Final post not found");
      }

      await deleteEngagementForTripFinalPost(tx, finalPost.id);

      await tx.tripFinalPost.delete({
        where: { tripId_userId: { tripId, userId } },
      });
    });
  }

  /**
   * The trip owner, a current participant, or someone who already has a post
   * on this trip (for example after leaving) can manage that person's post.
   */
  private static async assertCanAuthor(
    db: DbClient,
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
      where: { tripId_userId: { tripId, userId } },
      select: { id: true },
    });
    if (participant) {
      return;
    }

    const ownPost = await db.tripFinalPost.findUnique({
      where: { tripId_userId: { tripId, userId } },
      select: { id: true },
    });
    if (ownPost) {
      return;
    }

    throw new AuthorizationError(
      "Only people on this trip can create their own final post"
    );
  }
}

async function deleteEngagementForTripFinalPost(
  tx: PrismaTransactionClient,
  finalPostId: string
) {
  const postEntity = EntityType.TRIP_FINAL_POST;

  for (;;) {
    const candidates = await tx.comment.findMany({
      where: { entityType: postEntity, entityId: finalPostId },
      select: {
        id: true,
        _count: { select: { replies: true } },
      },
    });
    const leaves = candidates.filter((c) => c._count.replies === 0);
    if (leaves.length === 0) {
      break;
    }
    const ids = leaves.map((c) => c.id);
    await tx.like.deleteMany({
      where: {
        entityType: EntityType.COMMENT,
        entityId: { in: ids },
      },
    });
    await tx.comment.deleteMany({ where: { id: { in: ids } } });
  }

  await tx.like.deleteMany({
    where: { entityType: postEntity, entityId: finalPostId },
  });
  await tx.share.deleteMany({
    where: { entityType: postEntity, entityId: finalPostId },
  });
  await tx.notification.deleteMany({
    where: { entityType: postEntity, entityId: finalPostId },
  });
}

function ownEntries(trip: TripForFinalizer, userId: string) {
  return trip.threadEntries.filter((entry) => entry.authorId === userId);
}

function buildSummary(trip: TripForFinalizer, userId: string) {
  const durationDays = Math.max(
    1,
    Math.round(
      ((trip.endDate ?? trip.startDate).getTime() - trip.startDate.getTime()) /
        MS_IN_DAY
    ) + 1
  );
  const destinations = trip.destinations ?? [];
  const entries = ownEntries(trip, userId);
  const locationSet = new Set<string>();

  entries.forEach((entry) => {
    if (entry.place?.name) {
      locationSet.add(entry.place.name);
    } else if (entry.locationName) {
      locationSet.add(entry.locationName);
    }
  });

  const highlightedLocations = Array.from(locationSet).slice(0, 3);
  const textEntries = entries
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
      ? `${tripTitle || "Your trip"} was your ${durationDays}-day trip.`
      : `${tripTitle || destinationLabel} was your ${durationDays}-day trip through ${destinationLabel}.`;

  const summaryParts = [
    opening,
    highlightedLocations.length
      ? `Your highlights included ${highlightedLocations.join(", ")}.`
      : "This recap uses the notes and photos you added yourself.",
    textEntries.join(" "),
  ].filter(Boolean);

  let summary = summaryParts.join(" ").trim();
  if (summary.length < MIN_SUMMARY_LENGTH) {
    summary = `${summary} Edit it, keep your own photos, and publish when it feels like yours.`;
  }
  return summary.trim();
}

function selectCuratedMedia(trip: TripForFinalizer, userId: string) {
  const own = mediaFromEntries(
    trip.threadEntries.filter((entry) => postedOrUploadedBy(entry, userId))
  );
  const tagged = mediaFromEntries(
    trip.threadEntries.filter(
      (entry) =>
        !postedOrUploadedBy(entry, userId) && entryIncludesUser(entry, userId)
    )
  );

  const selected = takePhotos(own);
  for (const url of takePhotos(tagged)) {
    if (selected.length >= MAX_MEDIA_COUNT) break;
    if (!selected.includes(url)) selected.push(url);
  }

  for (const media of trip.media) {
    if (selected.length >= MAX_MEDIA_COUNT) break;
    if (media.uploadedById !== userId) continue;
    const url = usableImageUrl(media);
    if (url && !selected.includes(url)) selected.push(url);
  }

  return selected;
}

function postedOrUploadedBy(entry: ThreadEntryWithExtras, userId: string) {
  return entry.authorId === userId || entry.media?.uploadedById === userId;
}

function entryIncludesUser(entry: ThreadEntryWithExtras, userId: string) {
  return (entry.taggedUsers ?? []).some((tag) => tag.taggedUserId === userId);
}

function mediaFromEntries(entries: ThreadEntryWithExtras[]) {
  return entries.flatMap((entry) => {
    const url = usableImageUrl(entry.media);
    return url ? [{ url, createdAt: entry.createdAt }] : [];
  });
}

function takePhotos(items: { url: string; createdAt: Date }[]) {
  const selected: string[] = [];
  const perDay = new Set<string>();
  const extras: string[] = [];
  const sorted = [...items].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime()
  );

  for (const item of sorted) {
    const dayKey = item.createdAt.toISOString().substring(0, 10);
    if (!perDay.has(dayKey) && selected.length < MAX_MEDIA_COUNT) {
      selected.push(item.url);
      perDay.add(dayKey);
    } else if (!selected.includes(item.url)) {
      extras.push(item.url);
    }
  }

  for (const url of extras) {
    if (selected.length >= MAX_MEDIA_COUNT) break;
    if (!selected.includes(url)) selected.push(url);
  }

  return selected;
}

function usableImageUrl(
  media: {
    url: string | null;
    type: MediaType;
    processingStatus: MediaProcessingStatus;
  } | null
) {
  if (
    !media?.url ||
    media.type !== MediaType.IMAGE ||
    media.processingStatus === MediaProcessingStatus.FAILED
  ) {
    return null;
  }
  return media.url;
}

function generateDefaultCaption(trip: TripForFinalizer, userId: string) {
  const ownPlace = ownEntries(trip, userId).find(
    (entry) => entry.place?.name || entry.locationName
  );
  const primaryDestination =
    ownPlace?.place?.name?.trim() ||
    ownPlace?.locationName?.trim() ||
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

type TripMedia = {
  url: string | null;
  type: MediaType;
  processingStatus: MediaProcessingStatus;
  uploadedById: string;
};

type TripForFinalizer = Trip & {
  threadEntries: ThreadEntryWithExtras[];
  media: TripMedia[];
};

type ThreadEntryWithExtras = {
  id: string;
  authorId: string;
  contentText: string | null;
  createdAt: Date;
  mediaId: string | null;
  locationName: string | null;
  media: {
    url: string | null;
    type: MediaType;
    processingStatus: MediaProcessingStatus;
    uploadedById: string;
  } | null;
  taggedUsers?: { taggedUserId: string }[];
  place: {
    name: string;
  } | null;
};
