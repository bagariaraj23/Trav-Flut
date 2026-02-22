import { EntityType } from '@prisma/client'
import { prisma } from './prisma'

/**
 * Resolves the owner userId for an entity (post/entry/comment).
 * Used for like and comment notifications so we know who to notify.
 */
export async function getEntityOwner(
  entityType: EntityType,
  entityId: string
): Promise<string | null> {
  if (entityType === 'TRIP_FINAL_POST') {
    const post = await prisma.tripFinalPost.findUnique({
      where: { id: entityId },
      select: { trip: { select: { userId: true } } }
    })
    return post?.trip?.userId ?? null
  }
  if (entityType === 'TRIP_THREAD_ENTRY') {
    const entry = await prisma.tripThreadEntry.findUnique({
      where: { id: entityId },
      select: { authorId: true }
    })
    return entry?.authorId ?? null
  }
  if (entityType === 'COMMENT') {
    const comment = await prisma.comment.findUnique({
      where: { id: entityId },
      select: { userId: true }
    })
    return comment?.userId ?? null
  }
  return null
}

/**
 * Resolves the parent post (entityType, entityId) for a comment.
 * Used for comment-like notifications so we can deep link to the post + scroll to the comment.
 */
export async function getPostFromComment(
  commentId: string
): Promise<{ entityType: EntityType; entityId: string } | null> {
  const comment = await prisma.comment.findUnique({
    where: { id: commentId },
    select: { entityType: true, entityId: true }
  })
  if (!comment) return null
  return { entityType: comment.entityType, entityId: comment.entityId }
}

/**
 * Resolves tripId for a TRIP_THREAD_ENTRY. Returns null for other types.
 */
export async function getTripIdFromEntry(
  entryId: string
): Promise<string | null> {
  const entry = await prisma.tripThreadEntry.findUnique({
    where: { id: entryId },
    select: { tripId: true }
  })
  return entry?.tripId ?? null
}

/**
 * Resolves trip title for a trip id. Used for notification copy (e.g. "liked your entry in [title]").
 */
export async function getTripTitle(
  tripId: string
): Promise<string | null> {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: { title: true }
  })
  return trip?.title ?? null
}
