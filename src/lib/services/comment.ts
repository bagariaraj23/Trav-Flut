import { EntityType, Prisma } from '@prisma/client'
import { prisma } from '../prisma'
import { redis, memoryCache } from '../redis'
import { sanitizeInput } from '../security'

const COUNT_CACHE_TTL = 5 * 60 * 1000

function getCountCacheKey(entityType: EntityType, entityId: string): string {
  return `commentCount:${entityType}:${entityId}`
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
  return false
}

async function validateParentComment(commentId: string): Promise<{ entityType: EntityType; entityId: string } | null> {
  const parent = await prisma.comment.findUnique({
    where: { id: commentId },
    select: {
      id: true,
      entityType: true,
      entityId: true,
      parentCommentId: true
    }
  })
  if (!parent) {
    return null
  }
  if (parent.parentCommentId) {
    throw new Error('Nesting limited to one level only')
  }
  return { entityType: parent.entityType, entityId: parent.entityId }
}

async function incrementCommentCount(entityType: EntityType, entityId: string, tx: Prisma.TransactionClient): Promise<void> {
  if (entityType === 'TRIP_FINAL_POST') {
    await tx.tripFinalPost.update({
      where: { id: entityId },
      data: { commentCount: { increment: 1 } }
    })
  } else if (entityType === 'TRIP_THREAD_ENTRY') {
    await tx.tripThreadEntry.update({
      where: { id: entityId },
      data: { commentCount: { increment: 1 } }
    })
  }
}

async function decrementCommentCount(entityType: EntityType, entityId: string, tx: Prisma.TransactionClient): Promise<void> {
  if (entityType === 'TRIP_FINAL_POST') {
    const post = await tx.tripFinalPost.findUnique({ where: { id: entityId }, select: { commentCount: true } })
    if (post && post.commentCount > 0) {
      await tx.tripFinalPost.update({
        where: { id: entityId },
        data: { commentCount: { decrement: 1 } }
      })
    }
  } else if (entityType === 'TRIP_THREAD_ENTRY') {
    const entry = await tx.tripThreadEntry.findUnique({ where: { id: entityId }, select: { commentCount: true } })
    if (entry && entry.commentCount > 0) {
      await tx.tripThreadEntry.update({
        where: { id: entityId },
        data: { commentCount: { decrement: 1 } }
      })
    }
  }
}

async function getEntityOwner(entityType: EntityType, entityId: string): Promise<string | null> {
  if (entityType === 'TRIP_FINAL_POST') {
    const post = await prisma.tripFinalPost.findUnique({
      where: { id: entityId },
      select: { trip: { select: { userId: true } } }
    })
    return post?.trip?.userId || null
  }
  if (entityType === 'TRIP_THREAD_ENTRY') {
    const entry = await prisma.tripThreadEntry.findUnique({
      where: { id: entityId },
      select: { authorId: true }
    })
    return entry?.authorId || null
  }
  return null
}

export async function createComment(
  userId: string,
  entityType: EntityType,
  entityId: string,
  contentText: string,
  parentCommentId?: string
) {
  if (contentText.length < 1 || contentText.length > 500) {
    throw new Error('Comment must be between 1 and 500 characters')
  }

  const sanitizedText = sanitizeInput(contentText)
  if (sanitizedText.trim().length === 0) {
    throw new Error('Comment content is required')
  }

  let finalEntityType = entityType
  let finalEntityId = entityId

  if (parentCommentId) {
    const parentInfo = await validateParentComment(parentCommentId)
    if (!parentInfo) {
      throw new Error('Parent comment not found')
    }
    finalEntityType = parentInfo.entityType
    finalEntityId = parentInfo.entityId
  } else {
    const exists = await validateEntityExists(entityType, entityId)
    if (!exists) {
      throw new Error('Entity not found')
    }
  }

  return await prisma.$transaction(async (tx) => {
    const comment = await tx.comment.create({
      data: {
        userId,
        entityType: finalEntityType,
        entityId: finalEntityId,
        contentText: sanitizedText,
        parentCommentId: parentCommentId || null
      },
      include: {
        user: {
          select: {
            id: true,
            username: true,
            name: true,
            avatarUrl: true
          }
        }
      }
    })

    if (!parentCommentId) {
      await incrementCommentCount(finalEntityType, finalEntityId, tx)
      await invalidateCountCache(finalEntityType, finalEntityId)
    }

    return comment
  })
}

export async function updateComment(userId: string, commentId: string, newText: string) {
  if (newText.length < 1 || newText.length > 500) {
    throw new Error('Comment must be between 1 and 500 characters')
  }

  const sanitizedText = sanitizeInput(newText)
  if (sanitizedText.trim().length === 0) {
    throw new Error('Comment content is required')
  }

  const comment = await prisma.comment.findUnique({
    where: { id: commentId },
    select: { userId: true }
  })

  if (!comment) {
    throw new Error('Comment not found')
  }

  if (comment.userId !== userId) {
    throw new Error('Unauthorized')
  }

  return await prisma.comment.update({
    where: { id: commentId },
    data: {
      contentText: sanitizedText,
      updatedAt: new Date()
    },
    include: {
      user: {
        select: {
          id: true,
          username: true,
          name: true,
          avatarUrl: true
        }
      }
    }
  })
}

export async function deleteComment(userId: string, commentId: string) {
  return await prisma.$transaction(async (tx) => {
    const comment = await tx.comment.findUnique({
      where: { id: commentId },
      include: {
        replies: {
          select: { id: true }
        }
      }
    })

    if (!comment) {
      throw new Error('Comment not found')
    }

    const entityOwner = await getEntityOwner(comment.entityType, comment.entityId)
    const isAuthor = comment.userId === userId
    const isEntityOwner = entityOwner === userId

    if (!isAuthor && !isEntityOwner) {
      throw new Error('Unauthorized')
    }

    const replyIds = comment.replies.map(r => r.id)
    if (replyIds.length > 0) {
      await tx.comment.deleteMany({
        where: { id: { in: replyIds } }
      })
    }

    await tx.comment.delete({
      where: { id: commentId }
    })

    if (!comment.parentCommentId) {
      await decrementCommentCount(comment.entityType, comment.entityId, tx)
      await invalidateCountCache(comment.entityType, comment.entityId)
    }

    return { deleted: true, replyCount: replyIds.length }
  })
}

export async function getCommentsByEntity(
  entityType: EntityType,
  entityId: string,
  cursor?: string,
  limit: number = 20
) {
  const where: Prisma.CommentWhereInput = {
    entityType,
    entityId,
    parentCommentId: null
  }

  if (cursor) {
    where.id = { lt: cursor }
  }

  const comments = await prisma.comment.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      userId: true,
      entityType: true,
      entityId: true,
      contentText: true,
      parentCommentId: true,
      createdAt: true,
      updatedAt: true,
      user: {
        select: {
          id: true,
          username: true,
          name: true,
          avatarUrl: true
        }
      },
      _count: {
        select: {
          replies: true
        }
      }
    }
  })

  const hasMore = comments.length > limit
  const items = hasMore ? comments.slice(0, limit) : comments
  const nextCursor = hasMore ? items[items.length - 1].id : null

  return {
    items: items.map(item => ({
      ...item,
      replyCount: item._count.replies
    })),
    nextCursor,
    hasMore
  }
}

export async function getCommentReplies(
  commentId: string,
  cursor?: string,
  limit: number = 20
) {
  const where: Prisma.CommentWhereInput = {
    parentCommentId: commentId
  }

  if (cursor) {
    where.id = { lt: cursor }
  }

  const replies = await prisma.comment.findMany({
    where,
    take: limit + 1,
    orderBy: { createdAt: 'desc' },
    select: {
      id: true,
      userId: true,
      entityType: true,
      entityId: true,
      contentText: true,
      parentCommentId: true,
      createdAt: true,
      updatedAt: true,
      user: {
        select: {
          id: true,
          username: true,
          avatarUrl: true
        }
      }
    }
  })

  const hasMore = replies.length > limit
  const items = hasMore ? replies.slice(0, limit) : replies
  const nextCursor = hasMore ? items[items.length - 1].id : null

  return {
    items,
    nextCursor,
    hasMore
  }
}

