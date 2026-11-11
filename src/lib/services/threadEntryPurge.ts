import { EntityType } from "@prisma/client";
import { prisma, type PrismaTransactionClient } from "@/lib/prisma";
import { CloudinaryService } from "@/lib/cloudinary";

export type ThreadEntryMediaInfo = {
  mediaId: string | null;
  mediaPublicId: string | null;
};

/**
 * Deletes one thread entry and related engagement inside a transaction.
 * Caller must enforce permissions and trip rules. Decrements trip.entryCount.
 */
export async function purgeThreadEntryWithClient(
  tx: PrismaTransactionClient,
  tripId: string,
  entryId: string
): Promise<ThreadEntryMediaInfo> {
  const entry = await tx.tripThreadEntry.findUnique({
    where: { id: entryId },
    include: { media: { select: { id: true, publicId: true } } },
  });

  if (!entry || entry.tripId !== tripId) {
    throw new Error("Thread entry not found");
  }

  const mediaId = entry.mediaId;
  const mediaPublicId = entry.media?.publicId ?? null;

  const threadComments = await tx.comment.findMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: entryId,
    },
    select: { id: true, parentCommentId: true },
  });

  const replyIds = threadComments
    .filter((c) => c.parentCommentId != null)
    .map((c) => c.id);
  const topIds = threadComments
    .filter((c) => c.parentCommentId == null)
    .map((c) => c.id);
  const allCommentIds = [...replyIds, ...topIds];

  if (allCommentIds.length > 0) {
    await tx.like.deleteMany({
      where: {
        OR: [
          { entityType: EntityType.COMMENT, entityId: { in: allCommentIds } },
        ],
      },
    });
  }

  if (replyIds.length > 0) {
    await tx.comment.deleteMany({ where: { id: { in: replyIds } } });
  }
  if (topIds.length > 0) {
    await tx.comment.deleteMany({ where: { id: { in: topIds } } });
  }

  await tx.like.deleteMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: entryId,
    },
  });

  await tx.share.deleteMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: entryId,
    },
  });

  await tx.notification.deleteMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: entryId,
    },
  });

  await tx.placeShare.deleteMany({
    where: { threadEntryId: entryId },
  });

  await tx.tripThreadEntry.delete({
    where: { id: entryId },
  });

  await tx.trip.update({
    where: { id: tripId },
    data: {
      entryCount: { decrement: 1 },
      updatedAt: new Date(),
    },
  });

  return { mediaId, mediaPublicId };
}

/**
 * Deletes all entries authored by [authorId] on [tripId] in bulk.
 * Designed for participant leave flow to avoid per-entry transactional loops.
 * Returns media references for async post-transaction cleanup.
 */
export async function purgeAuthorThreadEntriesWithClient(
  tx: PrismaTransactionClient,
  tripId: string,
  authorId: string
): Promise<ThreadEntryMediaInfo[]> {
  const entries = await tx.tripThreadEntry.findMany({
    where: { tripId, authorId },
    select: {
      id: true,
      mediaId: true,
      media: { select: { publicId: true } },
    },
  });

  if (entries.length === 0) {
    return [];
  }

  const entryIds = entries.map((e) => e.id);
  const mediaRefs = entries.map((e) => ({
    mediaId: e.mediaId,
    mediaPublicId: e.media?.publicId ?? null,
  }));

  const threadComments = await tx.comment.findMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: { in: entryIds },
    },
    select: { id: true, parentCommentId: true },
  });

  const replyIds = threadComments
    .filter((c) => c.parentCommentId != null)
    .map((c) => c.id);
  const topIds = threadComments
    .filter((c) => c.parentCommentId == null)
    .map((c) => c.id);
  const allCommentIds = [...replyIds, ...topIds];

  if (allCommentIds.length > 0) {
    await tx.like.deleteMany({
      where: {
        entityType: EntityType.COMMENT,
        entityId: { in: allCommentIds },
      },
    });
  }
  if (replyIds.length > 0) {
    await tx.comment.deleteMany({ where: { id: { in: replyIds } } });
  }
  if (topIds.length > 0) {
    await tx.comment.deleteMany({ where: { id: { in: topIds } } });
  }

  await tx.like.deleteMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: { in: entryIds },
    },
  });
  await tx.share.deleteMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: { in: entryIds },
    },
  });
  await tx.notification.deleteMany({
    where: {
      entityType: EntityType.TRIP_THREAD_ENTRY,
      entityId: { in: entryIds },
    },
  });
  await tx.placeShare.deleteMany({
    where: { threadEntryId: { in: entryIds } },
  });
  await tx.tripThreadEntry.deleteMany({
    where: { id: { in: entryIds } },
  });

  await tx.trip.update({
    where: { id: tripId },
    data: {
      entryCount: { decrement: entryIds.length },
      updatedAt: new Date(),
    },
  });

  return mediaRefs;
}

export async function cleanupThreadEntryMedia(
  mediaId: string | null,
  mediaPublicId: string | null
): Promise<void> {
  if (!mediaId || !mediaPublicId) return;

  const tripsUsingCover = await prisma.trip.findMany({
    where: { coverMediaId: mediaId },
    select: { id: true },
  });
  if (tripsUsingCover.length > 0) {
    await prisma.trip.updateMany({
      where: { coverMediaId: mediaId },
      data: { coverMediaId: null },
    });
  }

  const otherRefs = await prisma.tripThreadEntry.count({
    where: { mediaId },
  });
  if (otherRefs === 0) {
    try {
      await CloudinaryService.deleteMedia(mediaPublicId);
    } catch (e) {
      console.error("[ThreadEntry] Cloudinary cleanup failed:", e);
    }
  }
}
