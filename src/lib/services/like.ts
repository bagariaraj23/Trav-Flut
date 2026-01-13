import { EntityType, Prisma } from '@prisma/client'
import { prisma } from '../prisma'
import { redis, memoryCache } from '../redis'

const COUNT_CACHE_TTL = 5 * 60 * 1000

function getCountCacheKey(entityType: EntityType, entityId: string): string {
  return `likeCount:${entityType}:${entityId}`
}

async function invalidateCountCache(entityType: EntityType, entityId: string): Promise<void> {
  const key = getCountCacheKey(entityType, entityId)
  memoryCache.delete(key)
  if (redis) {
    await redis.del(key)
  }
}

async function validateEntityExists(entityType: EntityType, entityId: string): Promise<boolean> {
  if (entityType === 'TRIP_FINAL_POST') {
    const post = await prisma.tripFinalPost.findUnique({ where: { id: entityId } })
    return post !== null
  }
  if (entityType === 'TRIP_THREAD_ENTRY') {
    const entry = await prisma.tripThreadEntry.findUnique({ where: { id: entityId } })
    return entry !== null
  }
  if (entityType === 'COMMENT') {
    const comment = await prisma.comment.findUnique({ where: { id: entityId } })
    return comment !== null
  }
  return false
}

async function incrementLikeCount(entityType: EntityType, entityId: string, tx: Prisma.TransactionClient): Promise<void> {
  if (entityType === 'TRIP_FINAL_POST') {
    await tx.tripFinalPost.update({
      where: { id: entityId },
      data: { likeCount: { increment: 1 } }
    })
  } else if (entityType === 'TRIP_THREAD_ENTRY') {
    await tx.tripThreadEntry.update({
      where: { id: entityId },
      data: { likeCount: { increment: 1 } }
    })
  }
}

async function decrementLikeCount(entityType: EntityType, entityId: string, tx: Prisma.TransactionClient): Promise<void> {
  if (entityType === 'TRIP_FINAL_POST') {
    const post = await tx.tripFinalPost.findUnique({ where: { id: entityId }, select: { likeCount: true } })
    if (post && post.likeCount > 0) {
      await tx.tripFinalPost.update({
        where: { id: entityId },
        data: { likeCount: { decrement: 1 } }
      })
    }
  } else if (entityType === 'TRIP_THREAD_ENTRY') {
    const entry = await tx.tripThreadEntry.findUnique({ where: { id: entityId }, select: { likeCount: true } })
    if (entry && entry.likeCount > 0) {
      await tx.tripThreadEntry.update({
        where: { id: entityId },
        data: { likeCount: { decrement: 1 } }
      })
    }
  }
}

export async function createLike(userId: string, entityType: EntityType, entityId: string) {
  const exists = await validateEntityExists(entityType, entityId)
  if (!exists) {
    throw new Error('Entity not found')
  }

  return await prisma.$transaction(async (tx) => {
    const existing = await tx.like.findFirst({
      where: { userId, entityType, entityId }
    })
    if (existing) {
      return existing
    }

    const like = await tx.like.create({
      data: { userId, entityType, entityId }
    })

    await incrementLikeCount(entityType, entityId, tx)

    await invalidateCountCache(entityType, entityId)

    return like
  })
}

export async function deleteLike(userId: string, entityType: EntityType, entityId: string) {
  return await prisma.$transaction(async (tx) => {
    const like = await tx.like.findFirst({
      where: { userId, entityType, entityId }
    })
    if (!like) {
      return null
    }

    await tx.like.delete({
      where: { id: like.id }
    })

    await decrementLikeCount(entityType, entityId, tx)

    await invalidateCountCache(entityType, entityId)

    return like
  })
}

export async function getLikesByEntity(
  entityType: EntityType,
  entityId: string,
  cursor?: string,
  limit: number = 20
) {
  const where: Prisma.LikeWhereInput = {
    entityType,
    entityId
  }

  if (cursor) {
    where.id = { lt: cursor }
  }

  const likes = await prisma.like.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      createdAt: true,
      user: {
        select: {
          id: true,
          username: true,
          avatarUrl: true
        }
      }
    }
  })

  const hasMore = likes.length > limit
  const items = hasMore ? likes.slice(0, limit) : likes
  const nextCursor = hasMore ? items[items.length - 1].id : null

  return {
    items,
    nextCursor,
    hasMore
  }
}

export async function checkLikeStatus(
  userId: string,
  entityType: EntityType,
  entityIds: string[]
): Promise<Record<string, boolean>> {
  if (entityIds.length === 0) {
    return {}
  }

  const likes = await prisma.like.findMany({
    where: {
      userId,
      entityType,
      entityId: { in: entityIds }
    },
    select: {
      entityId: true
    }
  })

  const likedSet = new Set(likes.map(l => l.entityId))
  const result: Record<string, boolean> = {}
  for (const entityId of entityIds) {
    result[entityId] = likedSet.has(entityId)
  }
  return result
}

export async function getUserLikes(
  userId: string,
  cursor?: string,
  limit: number = 20
) {
  const where: Prisma.LikeWhereInput = {
    userId
  }

  if (cursor) {
    where.id = { lt: cursor }
  }

  const likes = await prisma.like.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: 'desc' },
    include: {
      user: {
        select: {
          id: true,
          username: true,
          avatarUrl: true
        }
      }
    }
  })

  const hasMore = likes.length > limit
  const items = hasMore ? likes.slice(0, limit) : likes
  const nextCursor = hasMore ? items[items.length - 1].id : null

  return {
    items,
    nextCursor,
    hasMore
  }
}

