import { EntityType, ShareType, Prisma } from "@prisma/client";
import { prisma } from "../prisma";
import { redis, memoryCache } from "../redis";
import { nanoid } from "nanoid";

const SHARE_TOKEN_CACHE_TTL = 60 * 60 * 1000;

function getShareTokenCacheKey(shareToken: string): string {
  return `shareToken:${shareToken}`;
}

async function invalidateShareTokenCache(shareToken: string): Promise<void> {
  const key = getShareTokenCacheKey(shareToken);
  memoryCache.delete(key);
  if (redis) {
    await redis.del(key);
  }
}

async function validateEntityExists(
  entityType: EntityType,
  entityId: string
): Promise<boolean> {
  if (entityType === "TRIP_FINAL_POST") {
    const post = await prisma.tripFinalPost.findUnique({
      where: { id: entityId },
    });
    return post !== null;
  }
  return false;
}

async function incrementShareCount(
  entityType: EntityType,
  entityId: string,
  tx: Prisma.TransactionClient
): Promise<void> {
  if (entityType === "TRIP_FINAL_POST") {
    await tx.tripFinalPost.update({
      where: { id: entityId },
      data: { shareCount: { increment: 1 } },
    });
  }
}

export async function createShare(
  userId: string,
  entityType: EntityType,
  entityId: string,
  shareType: ShareType,
  expiresAt?: Date
) {
  const exists = await validateEntityExists(entityType, entityId);
  if (!exists) {
    throw new Error("Entity not found");
  }

  let shareToken: string;
  let isUnique = false;
  while (!isUnique) {
    shareToken = nanoid(16);
    const existing = await prisma.share.findUnique({
      where: { shareToken },
    });
    if (!existing) {
      isUnique = true;
    }
  }

  const metadata: Record<string, any> = {
    createdAt: new Date().toISOString(),
  };

  return await prisma.$transaction(async (tx) => {
    const share = await tx.share.create({
      data: {
        userId,
        entityType,
        entityId,
        shareToken: shareToken!,
        shareType,
        metadata,
        expiresAt,
      },
    });

    await incrementShareCount(entityType, entityId, tx);

    if (redis) {
      await redis.set(
        getShareTokenCacheKey(shareToken!),
        JSON.stringify(share),
        {
          ex: expiresAt
            ? Math.floor((expiresAt.getTime() - Date.now()) / 1000)
            : 3600,
        }
      );
    }

    return share;
  });
}

export async function resolveShareToken(shareToken: string) {
  const cacheKey = getShareTokenCacheKey(shareToken);

  let share: any = null;
  if (redis) {
    const cached = await redis.get<string>(cacheKey);
    if (cached) {
      try {
        share = JSON.parse(cached);
      } catch {
        await invalidateShareTokenCache(shareToken);
      }
    }
  }

  if (!share) {
    share = await prisma.share.findUnique({
      where: { shareToken },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            avatarUrl: true,
          },
        },
      },
    });

    if (share && redis) {
      const ttl = share.expiresAt
        ? Math.floor((share.expiresAt.getTime() - Date.now()) / 1000)
        : 3600;
      if (ttl > 0) {
        await redis.set(cacheKey, JSON.stringify(share), { ex: ttl });
      }
    }
  }

  if (!share) {
    throw new Error("Share token not found");
  }

  if (share.expiresAt && new Date(share.expiresAt) < new Date()) {
    await invalidateShareTokenCache(shareToken);
    throw new Error("Share token expired");
  }

  let entityData: any = null;
  if (share.entityType === "TRIP_FINAL_POST") {
    entityData = await prisma.tripFinalPost.findUnique({
      where: { id: share.entityId },
      include: {
        trip: {
          select: {
            id: true,
            title: true,
            userId: true,
            destinations: true,
          },
        },
      },
    });
  } else if (share.entityType === "TRIP_THREAD_ENTRY") {
    entityData = await prisma.tripThreadEntry.findUnique({
      where: { id: share.entityId },
      include: {
        trip: {
          select: {
            id: true,
            title: true,
          },
        },
        author: {
          select: {
            id: true,
            username: true,
            avatarUrl: true,
          },
        },
      },
    });
  } else if (share.entityType === "COMMENT") {
    entityData = await prisma.comment.findUnique({
      where: { id: share.entityId },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            avatarUrl: true,
          },
        },
      },
    });
  }

  return {
    share,
    entity: entityData,
  };
}

export async function trackShareOpen(
  shareToken: string,
  metadata: Record<string, any>
) {
  const share = await prisma.share.findUnique({
    where: { shareToken },
    select: { id: true, metadata: true },
  });

  if (!share) {
    throw new Error("Share token not found");
  }

  const currentMetadata = (share.metadata as Record<string, any>) || {};
  const updatedMetadata = {
    ...currentMetadata,
    opens: (currentMetadata.opens || []).concat({
      timestamp: new Date().toISOString(),
      platform: metadata.platform || "unknown",
      location: metadata.location || null,
      userAgent: metadata.userAgent || null,
    }),
  };

  await prisma.share.update({
    where: { id: share.id },
    data: { metadata: updatedMetadata },
  });

  await invalidateShareTokenCache(shareToken);
}

export async function getSharesByUser(
  userId: string,
  cursor?: string,
  limit: number = 20
) {
  const where: Prisma.ShareWhereInput = {
    userId,
  };

  if (cursor) {
    where.id = { lt: cursor };
  }

  const shares = await prisma.share.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: "desc" },
    include: {
      user: {
        select: {
          id: true,
          username: true,
          avatarUrl: true,
        },
      },
    },
  });

  const hasMore = shares.length > limit;
  const items = hasMore ? shares.slice(0, limit) : shares;
  const nextCursor = hasMore ? items[items.length - 1].id : null;

  const itemsWithEntity = await Promise.all(
    items.map(async (share) => {
      let entityPreview: any = null;
      if (share.entityType === "TRIP_FINAL_POST") {
        const post = await prisma.tripFinalPost.findUnique({
          where: { id: share.entityId },
          select: {
            id: true,
            summaryText: true,
            trip: {
              select: {
                id: true,
                title: true,
              },
            },
          },
        });
        entityPreview = post;
      } else if (share.entityType === "TRIP_THREAD_ENTRY") {
        const entry = await prisma.tripThreadEntry.findUnique({
          where: { id: share.entityId },
          select: {
            id: true,
            contentText: true,
            trip: {
              select: {
                id: true,
                title: true,
              },
            },
          },
        });
        entityPreview = entry;
      } else if (share.entityType === "COMMENT") {
        const comment = await prisma.comment.findUnique({
          where: { id: share.entityId },
          select: {
            id: true,
            contentText: true,
            user: {
              select: {
                id: true,
                username: true,
              },
            },
          },
        });
        entityPreview = comment;
      }

      return {
        ...share,
        entityPreview,
      };
    })
  );

  return {
    items: itemsWithEntity,
    nextCursor,
    hasMore,
  };
}

export function generateDeepLink(
  entityType: EntityType,
  entityId: string
): string {
  const baseUrl = process.env.DEEP_LINK_BASE_URL || "tripthread://";
  return `${baseUrl}${entityType.toLowerCase()}/${entityId}`;
}
