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

export async function createLike(
  userId: string,
  entityType: EntityType,
  entityId: string
) {
  const exists = await validateEntityExists(entityType, entityId);
  if (!exists) {
    throw new Error("Entity not found");
  }

  return await prisma.$transaction(async (tx) => {
    const existing = await tx.like.findFirst({
      where: { userId, entityType, entityId },
    });
    if (existing) {
      return existing;
    }

    const like = await tx.like.create({
      data: { userId, entityType, entityId },
    });

    await incrementEntityCount(entityType, entityId, "likeCount", tx);

    await invalidateEngagementCache("like", entityType, entityId);

    return like;
  });
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
