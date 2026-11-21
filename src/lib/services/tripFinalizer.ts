import { prisma, type PrismaTransactionClient } from "@/lib/prisma";
import {
  EntityType,
  FinalPostTemplateChoice,
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
import { allowedFinalPostUrls } from "./postMedia";

const MIN_MEDIA_COUNT = 1;

const TEMPLATE_CHOICES = new Set<string>([
  FinalPostTemplateChoice.postcard,
  FinalPostTemplateChoice.map_first,
  FinalPostTemplateChoice.thread_reel,
]);

const finalPostSelect = {
  id: true,
  tripId: true,
  userId: true,
  summaryText: true,
  curatedMedia: true,
  caption: true,
  coverMediaUrl: true,
  templateChoice: true,
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
  templateChoice?: FinalPostTemplateChoice;
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
    await insertDrafts(db, [
      {
        tripId,
        userId,
        summaryText: draft.summaryText,
        curatedMedia: draft.curatedMedia,
        caption: draft.caption,
        coverMediaUrl: draft.coverMediaUrl,
      },
    ]);
    const saved = await db.tripFinalPost.findUnique({
      where: { tripId_userId: { tripId, userId } },
      select: finalPostSelect,
    });
    if (!saved) {
      throw new ConflictError("Final post could not be saved");
    }
    return saved;
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
    const missing = memberIds.flatMap((memberId) => {
      if (existingByUser.has(memberId)) return [];
      const draft = buildMemberFinalDraft(draftTrip, memberId);
      return [
        {
          tripId,
          userId: memberId,
          summaryText: draft.summaryText,
          curatedMedia: draft.curatedMedia,
          caption: draft.caption,
          coverMediaUrl: draft.coverMediaUrl,
        },
      ];
    });
    await insertDrafts(db, missing);
    if (missing.length > 0) {
      const created = await db.tripFinalPost.findMany({
        where: { tripId, userId: { in: missing.map((row) => row.userId) } },
        select: finalPostSelect,
      });
      for (const post of created) existingByUser.set(post.userId, post);
    }
    return memberIds.map((memberId) => {
      const post = existingByUser.get(memberId);
      if (!post) {
        throw new ConflictError("Final post could not be saved");
      }
      return post;
    });
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
      const candidates = [
        ...(Array.isArray(updates.curatedMedia) ? updates.curatedMedia : []),
        ...(updates.coverMediaUrl ? [updates.coverMediaUrl] : []),
      ];
      const allowedMedia = mediaChanged
        ? await allowedFinalPostUrls(tx, tripId, userId, candidates)
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

      if (updates.templateChoice !== undefined) {
        if (!TEMPLATE_CHOICES.has(updates.templateChoice)) {
          throw new ValidationError(
            "templateChoice must be postcard, map_first, or thread_reel"
          );
        }
        data.templateChoice = updates.templateChoice;
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

      const allowedMedia = await allowedFinalPostUrls(tx, tripId, userId, [
        ...(finalPost.curatedMedia ?? []),
        ...(finalPost.coverMediaUrl ? [finalPost.coverMediaUrl] : []),
      ]);
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

/**
 * Insert drafts with ON CONFLICT DO NOTHING.
 * A caught P2002 aborts the surrounding Postgres transaction, so a concurrent
 * end (the owner and the hourly job) must not throw. The caller reads the rows
 * back, whether this call inserted them or the other transaction did.
 */
async function insertDrafts(
  db: DbClient,
  rows: Array<{
    tripId: string;
    userId: string;
    summaryText: string;
    curatedMedia: string[];
    caption: string | null;
    coverMediaUrl: string | null;
  }>
) {
  if (rows.length === 0) return;
  await db.tripFinalPost.createMany({
    data: rows.map((row) => ({
      ...row,
      generationStatus: GenerationStatus.DRAFT,
    })),
    skipDuplicates: true,
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

/**
 * Keep photos from this trip, or photos this author uploaded from their phone.
 * A Cloudinary prefix is not enough: other people's private photos use the same account.
 */
function sanitizeMedia(urls: string[], allowed: Set<string>) {
  const seen = new Set<string>();
  const kept: string[] = [];
  for (const raw of urls) {
    const url = raw?.trim();
    if (!url || seen.has(url)) continue;
    if (!allowed.has(url)) {
      throw new ValidationError(
        "Choose a photo from this trip or upload one from your phone"
      );
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
    throw new ValidationError(
      "Choose a photo from this trip or upload one from your phone"
    );
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
