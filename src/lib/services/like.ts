import { EntityType } from "@prisma/client";
import { prisma } from "../prisma";
import {
  validateEntityExists,
  invalidateEngagementCache,
  incrementEntityCount,
  decrementEntityCount,
  paginateResults,
  USER_FULL_SELECT,
  ENGAGEMENT_CONSTANTS,
} from "./engagement-utils";
import { getEntityOwner, getPostFromComment, getTripIdFromEntry } from "../entity-owner";
import { createNotification } from "./notification";
import { NotFoundError, DatabaseError } from "../errors";

export async function createLike(
  userId: string,
  entityType: EntityType,
  entityId: string
) {
  const exists = await validateEntityExists(entityType, entityId);
  if (!exists) {
    throw new NotFoundError("Entity not found");
  }

  let isNewLike = true;
  let like: Awaited<ReturnType<typeof prisma.like.create>>;
  try {
    like = await prisma.$transaction(async (tx) => {
      const newLike = await tx.like.create({
        data: { userId, entityType, entityId },
      });
      await incrementEntityCount(entityType, entityId, "likeCount", tx);
      await invalidateEngagementCache("like", entityType, entityId);
      return newLike;
    });
  } catch (error: any) {
    if (error?.code === "P2002") {
      // Idempotent like behavior under race: another request created the same like.
      const existingLike = await prisma.like.findFirst({
        where: { userId, entityType, entityId },
      });
      if (existingLike) {
        isNewLike = false;
        like = existingLike;
      } else {
        throw new DatabaseError("Failed to create like");
      }
    } else {
      throw error;
    }
  }

  if (!isNewLike) {
    return like;
  }

  // Fire-and-forget: create notification without blocking response
  void (async () => {
    try {
      const recipientId = await getEntityOwner(entityType, entityId);
      if (!recipientId) return;

      if (entityType === "COMMENT") {
        const [post, comment] = await Promise.all([
          getPostFromComment(entityId),
          prisma.comment.findUnique({
            where: { id: entityId },
            select: { contentText: true },
          }),
        ]);
        if (!post) return;
        const contentPreview =
          comment?.contentText != null
            ? comment.contentText.length > 60
              ? comment.contentText.slice(0, 60) + "..."
              : comment.contentText
            : undefined;
        const tripId =
          post.entityType === "TRIP_THREAD_ENTRY"
            ? await getTripIdFromEntry(post.entityId)
            : null;
        await createNotification({
          type: "LIKE",
          actorId: userId,
          recipientId,
          entityType: "COMMENT",
          entityId,
          metadata: {
            postEntityType: post.entityType,
            postEntityId: post.entityId,
            ...(contentPreview && { contentPreview }),
            ...(tripId && { tripId }),
            ...(post.entityType === "TRIP_THREAD_ENTRY" && {
              threadEntryId: post.entityId,
            }),
          },
        });
      } else if (entityType === "TRIP_THREAD_ENTRY") {
        const tripId = await getTripIdFromEntry(entityId);
        await createNotification({
          type: "LIKE",
          actorId: userId,
          recipientId,
          entityType,
          entityId,
          metadata: {
            ...(tripId && { tripId }),
            threadEntryId: entityId,
          },
        });
      } else {
        await createNotification({
          type: "LIKE",
          actorId: userId,
          recipientId,
          entityType,
          entityId,
        });
      }
    } catch (err) {
      console.error(
        "[Notification] Failed to create LIKE notification:",
        { entityType, entityId, actorId: userId, error: err }
      );
    }
  })();

  return like;
}

export async function deleteLike(
  userId: string,
  entityType: EntityType,
  entityId: string
) {
  return await prisma.$transaction(async (tx) => {
    const like = await tx.like.findFirst({
      where: { userId, entityType, entityId },
    });
    if (!like) {
      return null;
    }

    await tx.like.delete({
      where: { id: like.id },
    });

    await decrementEntityCount(entityType, entityId, "likeCount", tx);

    await invalidateEngagementCache("like", entityType, entityId);

    return like;
  });
}

export async function getLikesByEntity(
  entityType: EntityType,
  entityId: string,
  cursor?: string,
  limit: number = ENGAGEMENT_CONSTANTS.PAGINATION.DEFAULT_LIMIT
) {
  const where: any = {
    entityType,
    entityId,
    user: {
      deletedAt: null,
    },
  };

  if (cursor) {
    where.id = { lt: cursor };
  }

  const likes = await prisma.like.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: "desc" },
    select: {
      id: true,
      createdAt: true,
      user: {
        select: USER_FULL_SELECT,
      },
    },
  });

  // Filter out any likes with null users (safety check)
  const validLikes = likes.filter((like) => like.user !== null);
  return paginateResults(validLikes, limit);
}

export async function checkLikeStatus(
  userId: string,
  entityType: EntityType,
  entityIds: string[]
): Promise<Record<string, boolean>> {
  if (entityIds.length === 0) {
    return {};
  }

  const likes = await prisma.like.findMany({
    where: {
      userId,
      entityType,
      entityId: { in: entityIds },
    },
    select: {
      entityId: true,
    },
  });

  const likedSet = new Set(likes.map((l) => l.entityId));
  const result: Record<string, boolean> = {};
  for (const entityId of entityIds) {
    result[entityId] = likedSet.has(entityId);
  }
  return result;
}

export async function getUserLikes(
  userId: string,
  cursor?: string,
  limit: number = ENGAGEMENT_CONSTANTS.PAGINATION.DEFAULT_LIMIT
) {
  const where: any = {
    userId,
    user: {
      deletedAt: null,
    },
  };

  if (cursor) {
    where.id = { lt: cursor };
  }

  const likes = await prisma.like.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: "desc" },
    include: {
      user: {
        select: USER_FULL_SELECT,
      },
    },
  });

  // Filter out any likes with null users (safety check)
  const validLikes = likes.filter((like) => like.user !== null);
  return paginateResults(validLikes, limit);
}
