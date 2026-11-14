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
import {
  buildMemberFinalDraft,
  MAX_CURATED_MEDIA,
  MIN_SUMMARY_LENGTH,
  type DraftTrip,
} from "../../../scheduler/src/memberFinalDraft";

const MIN_MEDIA_COUNT = 1;

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
    // The first ending creates the personal draft. Later calls leave that draft,
    // including anything the member has edited, exactly as it is.
    if (existing) {
      return existing;
    }

    const draft = await this.composeDraft(db, tripId, userId);
    return db.tripFinalPost.create({
      data: {
        tripId,
        userId,
        summaryText: draft.summaryText,
        curatedMedia: draft.curatedMedia,
        caption: draft.caption,
        coverMediaUrl: draft.coverMediaUrl,
        generationStatus: GenerationStatus.DRAFT,
      },
      select: finalPostSelect,
    });
  }

  private static async composeDraft(db: DbClient, tripId: string, userId: string) {
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

    return buildMemberFinalDraft(toDraftTrip(trip as TripForFinalizer), userId);
  }

  /**
   * Draft a personal post for the owner and every current participant.
   * The trip, its entries, and its media are loaded once. Each member's draft
   * is then built in memory, matching the scheduler.
   */
  static async generateFinalPostsForMembers(tripId: string, tx?: DbClient) {
    const db = tx || prisma;
    const tripData = await db.trip.findUnique({
      where: { id: tripId },
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

    if (!tripData) {
      throw new NotFoundError("Trip not found");
    }

    const draftTrip = toDraftTrip(tripData as TripForFinalizer);
    const memberIds = [
      ...new Set([
        tripData.userId,
        ...tripData.participants.map((participant) => participant.userId),
      ]),
    ];
    const existing = await db.tripFinalPost.findMany({
      where: { tripId, userId: { in: memberIds } },
      select: finalPostSelect,
    });
    const existingByUser = new Map(existing.map((post) => [post.userId, post]));
    const posts = [];
    for (const memberId of memberIds) {
      const already = existingByUser.get(memberId);
      if (already) {
        posts.push(already);
        continue;
      }
      const draft = buildMemberFinalDraft(draftTrip, memberId);
      posts.push(
        await db.tripFinalPost.create({
          data: {
            tripId,
            userId: memberId,
            summaryText: draft.summaryText,
            curatedMedia: draft.curatedMedia,
            caption: draft.caption,
            coverMediaUrl: draft.coverMediaUrl,
            generationStatus: GenerationStatus.DRAFT,
          },
          select: finalPostSelect,
        })
      );
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

      const mediaChanged =
        Array.isArray(updates.curatedMedia) ||
        updates.coverMediaUrl !== undefined;
      const allowedMedia = mediaChanged
        ? await tripMediaUrls(tx, tripId)
        : null;

      if (Array.isArray(updates.curatedMedia)) {
        data.curatedMedia = sanitizeMedia(updates.curatedMedia, allowedMedia!);
        if (data.curatedMedia.length > MAX_CURATED_MEDIA) {
          data.curatedMedia = data.curatedMedia.slice(0, MAX_CURATED_MEDIA);
        }
      }

      if (updates.caption !== undefined) {
        data.caption = updates.caption?.trim() || null;
      }

      if (updates.coverMediaUrl !== undefined) {
        data.coverMediaUrl = coverFromTrip(updates.coverMediaUrl, allowedMedia!);
      } else if (data.curatedMedia && data.curatedMedia.length > 0) {
        data.coverMediaUrl = data.curatedMedia[0];
      }

      return tx.tripFinalPost.update({
        where: { tripId_userId: { tripId, userId } },
        data: {
          ...data,
          generationStatus: wasPublished
            ? GenerationStatus.PUBLISHED
            : GenerationStatus.DRAFT,
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

      const allowedMedia = await tripMediaUrls(tx, tripId);
      sanitizeMedia(finalPost.curatedMedia ?? [], allowedMedia);
      if (finalPost.coverMediaUrl) {
        coverFromTrip(finalPost.coverMediaUrl, allowedMedia);
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

function toDraftTrip(trip: TripForFinalizer): DraftTrip {
  return {
    title: trip.title,
    startDate: trip.startDate,
    endDate: trip.endDate,
    destinations: trip.destinations ?? [],
    mood: trip.mood,
    entries: trip.threadEntries.map((entry) => ({
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
      taggedUserIds: (entry.taggedUsers ?? []).map((tag) => tag.taggedUserId),
      placeName: entry.place?.name ?? null,
    })),
    uploadedMedia: trip.media.map((media) => ({
      url: media.url,
      type: media.type,
      processingStatus: media.processingStatus,
      uploadedById: media.uploadedById,
    })),
  };
}

/** Photos already uploaded to this trip, including photos on thread entries. */
async function tripMediaUrls(db: DbClient, tripId: string) {
  const trip = await db.trip.findUnique({
    where: { id: tripId },
    select: {
      media: { select: { url: true } },
      threadEntries: { select: { media: { select: { url: true } } } },
    },
  });
  const urls = new Set<string>();
  for (const media of trip?.media ?? []) {
    if (media.url) urls.add(media.url);
  }
  for (const entry of trip?.threadEntries ?? []) {
    if (entry.media?.url) urls.add(entry.media.url);
  }
  return urls;
}

/**
 * Keep only photos that belong to this trip.
 * A Cloudinary prefix is not enough: other people's private photos use the same account.
 */
function sanitizeMedia(urls: string[], allowed: Set<string>) {
  const seen = new Set<string>();
  const kept: string[] = [];
  for (const raw of urls) {
    const url = raw?.trim();
    if (!url || seen.has(url)) continue;
    if (!allowed.has(url)) {
      throw new ValidationError("Choose photos from this trip");
    }
    seen.add(url);
    kept.push(url);
  }
  return kept;
}

function coverFromTrip(url: string | null, allowed: Set<string>) {
  const trimmed = url?.trim() || null;
  if (!trimmed) return null;
  if (!allowed.has(trimmed)) {
    throw new ValidationError("Choose photos from this trip");
  }
  return trimmed;
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
