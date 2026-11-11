import { EntityType } from "@prisma/client";
import { prisma, type PrismaTransactionClient } from "../prisma";
import { redis, memoryCache } from "../redis";

// CONSTANTS
export const ENGAGEMENT_CONSTANTS = {
  PAGINATION: {
    DEFAULT_LIMIT: 20,
    MAX_LIMIT: 100,
  },
  CACHE_TTL: {
    COUNT: 5 * 60 * 1000, // 5 minutes
    SHARE_TOKEN: 60 * 60 * 1000, // 1 hour
  },
  SHARE: {
    TOKEN_LENGTH: 16,
    MAX_RETRY_ATTEMPTS: 10,
  },
  COMMENT: {
    MIN_LENGTH: 1,
    MAX_LENGTH: 250,
  },
} as const;

// USER SELECT CONSTANTS
export const USER_PUBLIC_SELECT = {
  id: true,
  username: true,
  name: true,
  avatarUrl: true,
} as const;

export const USER_PROFILE_SELECT = {
  ...USER_PUBLIC_SELECT,
  bio: true,
  isPrivate: true,
  createdAt: true,
} as const;

export const USER_MINIMAL_SELECT = {
  id: true,
  username: true,
  avatarUrl: true,
} as const;

export const USER_FULL_SELECT = {
  ...USER_PROFILE_SELECT,
  email: true,
  updatedAt: true,
  deletedAt: true,
  deleteMeta: true,
} as const;

// ENTITY VALIDATION
/**
 * Validates that an entity exists in the database
 * @param entityType - The type of entity (TRIP_FINAL_POST, TRIP_THREAD_ENTRY, COMMENT)
 * @param entityId - The ID of the entity
 * @returns true if entity exists, false otherwise
 */
export async function validateEntityExists(
  entityType: EntityType,
  entityId: string
): Promise<boolean> {
  switch (entityType) {
    case "TRIP_FINAL_POST":
      return !!(await prisma.tripFinalPost.findUnique({
        where: { id: entityId },
      }));
    case "TRIP_THREAD_ENTRY":
      return !!(await prisma.tripThreadEntry.findUnique({
        where: { id: entityId },
      }));
    case "COMMENT":
      return !!(await prisma.comment.findUnique({
        where: { id: entityId },
      }));
    default:
      return false;
  }
}

// CACHE MANAGEMENT
/**
 * Invalidates engagement-related cache entries
 * @param cacheType - Type of cache (like, comment, share)
 * @param entityType - The entity type
 * @param entityId - The entity ID
 */
export async function invalidateEngagementCache(
  cacheType: "like" | "comment" | "share",
  entityType: EntityType,
  entityId: string
): Promise<void> {
  const key = `${cacheType}Count:${entityType}:${entityId}`;
  memoryCache.delete(key);
  if (redis) {
    try {
      await redis.del(key);
    } catch (err) {
      console.warn("[engagement] Redis cache invalidate failed (non-fatal)", {
        key,
        error: err,
      });
    }
  }
}

// PAGINATION
export interface PaginatedResult<T> {
  items: T[];
  nextCursor: string | null;
  hasMore: boolean;
}

/**
 * Paginates a list of items using cursor-based pagination
 * @param items - Array of items with id field
 * @param limit - Maximum number of items to return
 * @returns Paginated result with items, cursor, and hasMore flag
 */
export function paginateResults<T extends { id: string }>(
  items: T[],
  limit: number
): PaginatedResult<T> {
  const hasMore = items.length > limit;
  const results = hasMore ? items.slice(0, limit) : items;
  const nextCursor = hasMore ? results[results.length - 1].id : null;

  return {
    items: results,
    nextCursor,
    hasMore,
  };
}

// COUNT MANAGEMENT
type CountType = "likeCount" | "commentCount" | "shareCount";

/**
 * Increments the engagement count for an entity
 * @param entityType - The entity type
 * @param entityId - The entity ID
 * @param countType - The type of count to increment
 * @param tx - Prisma transaction client
 */
export async function incrementEntityCount(
  entityType: EntityType,
  entityId: string,
  countType: CountType,
  tx: PrismaTransactionClient
): Promise<void> {
  switch (entityType) {
    case "TRIP_FINAL_POST":
      await tx.tripFinalPost.update({
        where: { id: entityId },
        data: { [countType]: { increment: 1 } },
      });
      break;
    case "TRIP_THREAD_ENTRY":
      await tx.tripThreadEntry.update({
        where: { id: entityId },
        data: { [countType]: { increment: 1 } },
      });
      break;
    case "COMMENT":
      // Comments don't have commentCount on themselves
      if (countType !== "commentCount") {
        await tx.comment.update({
          where: { id: entityId },
          data: { [countType]: { increment: 1 } },
        });
      }
      break;
  }
}

/**
 * Decrements the engagement count for an entity (with safety check to prevent negative counts)
 * @param entityType - The entity type
 * @param entityId - The entity ID
 * @param countType - The type of count to decrement
 * @param tx - Prisma transaction client
 */
export async function decrementEntityCount(
  entityType: EntityType,
  entityId: string,
  countType: CountType,
  tx: PrismaTransactionClient
): Promise<void> {
  switch (entityType) {
    case "TRIP_FINAL_POST": {
      const entity = await tx.tripFinalPost.findUnique({
        where: { id: entityId },
        select: { [countType]: true },
      });
      const currentCount = (entity as any)?.[countType] ?? 0;
      if (typeof currentCount === "number" && currentCount > 0) {
        await tx.tripFinalPost.update({
          where: { id: entityId },
          data: { [countType]: { decrement: 1 } },
        });
      }
      break;
    }
    case "TRIP_THREAD_ENTRY": {
      const entity = await tx.tripThreadEntry.findUnique({
        where: { id: entityId },
        select: { [countType]: true },
      });
      const currentCount = (entity as any)?.[countType] ?? 0;
      if (typeof currentCount === "number" && currentCount > 0) {
        await tx.tripThreadEntry.update({
          where: { id: entityId },
          data: { [countType]: { decrement: 1 } },
        });
      }
      break;
    }
    case "COMMENT": {
      // Comments don't have commentCount on themselves
      if (countType !== "commentCount") {
        const entity = await tx.comment.findUnique({
          where: { id: entityId },
          select: { [countType]: true },
        });
        const currentCount = (entity as any)?.[countType] ?? 0;
        if (typeof currentCount === "number" && currentCount > 0) {
          await tx.comment.update({
            where: { id: entityId },
            data: { [countType]: { decrement: 1 } },
          });
        }
      }
      break;
    }
  }
}
