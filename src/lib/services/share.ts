import { EntityType, ShareType } from "@prisma/client";
import { prisma } from "../prisma";
import { redis, memoryCache } from "../redis";
import { nanoid } from "nanoid";
import {
  validateEntityExists,
  incrementEntityCount,
  paginateResults,
  USER_MINIMAL_SELECT,
  ENGAGEMENT_CONSTANTS,
} from "./engagement-utils";

function getShareTokenCacheKey(shareToken: string): string {
  return `shareToken:${shareToken}`;
}

async function invalidateShareTokenCache(shareToken: string): Promise<void> {
  const key = getShareTokenCacheKey(shareToken);
  memoryCache.delete(key);
  if (redis) {
    try {
      await redis.del(key);
    } catch (err) {
      console.warn("[share] Redis cache invalidate failed (non-fatal)", {
        key,
        error: err,
      });
    }
  }
}

export type ShareSource = "SYSTEM_SHEET" | "IN_APP_DM";

export async function createShare(
  userId: string,
  entityType: EntityType,
  entityId: string,
  shareType: ShareType,
  expiresAt?: Date,
  shareSource: ShareSource = "SYSTEM_SHEET"
) {
  const exists = await validateEntityExists(entityType, entityId);
  if (!exists) {
    throw new Error("Entity not found");
  }

  // Generate unique share token with retry limit
  let shareToken: string;
  let attempts = 0;

  while (attempts < ENGAGEMENT_CONSTANTS.SHARE.MAX_RETRY_ATTEMPTS) {
    shareToken = nanoid(ENGAGEMENT_CONSTANTS.SHARE.TOKEN_LENGTH);
    const existing = await prisma.share.findUnique({
      where: { shareToken },
    });
    if (!existing) {
      break;
    }
    attempts++;
  }

  if (attempts >= ENGAGEMENT_CONSTANTS.SHARE.MAX_RETRY_ATTEMPTS) {
    throw new Error(
      "Failed to generate unique share token after maximum attempts"
    );
  }

  const metadata: Record<string, any> = {
    createdAt: new Date().toISOString(),
    shareSource,
  };

  const createData = {
    userId,
    entityType,
    entityId,
    shareToken: shareToken!,
    shareType,
    metadata,
    expiresAt,
  };

  // SYSTEM_SHEET does not bump shareCount — use a plain create to avoid holding an
  // interactive transaction open (Neon/slow pools + default ~5s tx timeout caused
  // INSERT-then-ROLLBACK 500s in logs).
  const share =
    shareSource === "IN_APP_DM"
      ? await prisma.$transaction(
          async (tx) => {
            const created = await tx.share.create({ data: createData });
            await incrementEntityCount(entityType, entityId, "shareCount", tx);
            return created;
          },
          { maxWait: 15_000, timeout: 20_000 }
        )
      : await prisma.share.create({ data: createData });

  if (redis) {
    try {
      const ttlSeconds = expiresAt
        ? Math.floor((expiresAt.getTime() - Date.now()) / 1000)
        : Math.floor(ENGAGEMENT_CONSTANTS.CACHE_TTL.SHARE_TOKEN / 1000);

      if (ttlSeconds > 0) {
        await redis.set(
          getShareTokenCacheKey(shareToken!),
          JSON.stringify(share),
          { ex: ttlSeconds }
        );
      }
    } catch (err) {
      console.warn("[share] Redis cache set failed (non-fatal)", {
        shareToken: shareToken!,
        error: err,
      });
    }
  }

  return share;
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
          select: USER_MINIMAL_SELECT,
        },
      },
    });

    if (share && redis) {
      const ttl = share.expiresAt
        ? Math.floor((share.expiresAt.getTime() - Date.now()) / 1000)
        : Math.floor(ENGAGEMENT_CONSTANTS.CACHE_TTL.SHARE_TOKEN / 1000);
      if (ttl > 0) {
        await redis.set(cacheKey, JSON.stringify(share), { ex: ttl });
      }
    }
  }

  if (!share) {
    throw new Error("Share token not found");
  }

  if (share.expiresAt && new Date(share.expiresAt) < new Date()) {
    // Lazy deletion: Delete expired share from database
    await prisma.share.delete({ where: { id: share.id } });
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
          select: USER_MINIMAL_SELECT,
        },
      },
    });
  } else if (share.entityType === "COMMENT") {
    entityData = await prisma.comment.findUnique({
      where: { id: share.entityId },
      include: {
        user: {
          select: USER_MINIMAL_SELECT,
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
  limit: number = ENGAGEMENT_CONSTANTS.PAGINATION.DEFAULT_LIMIT
) {
  const where: any = {
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
        select: USER_MINIMAL_SELECT,
      },
    },
  });

  const result = paginateResults(shares, limit);

  const itemsWithEntity = await Promise.all(
    result.items.map(async (share) => {
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
              select: USER_MINIMAL_SELECT,
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
    ...result,
    items: itemsWithEntity,
  };
}

export function generateDeepLink(
  entityType: EntityType,
  entityId: string
): string {
  const baseUrl = process.env.DEEP_LINK_BASE_URL || "tripthread://";
  return `${baseUrl}${entityType.toLowerCase()}/${entityId}`;
}
