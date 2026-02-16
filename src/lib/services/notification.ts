import type { EntityType, NotificationType, Prisma } from '@prisma/client'
import { prisma } from '../prisma'

export type CreateNotificationParams = {
  type: 'LIKE' | 'COMMENT' | 'COMMENT_REPLY' | 'TAG'
  actorId: string
  recipientId: string
  entityType?: EntityType
  entityId?: string
  metadata?: Record<string, unknown>
}

export type UnifiedNotificationItem = {
  type: 'FOLLOW_REQUEST' | 'LIKE' | 'COMMENT' | 'COMMENT_REPLY' | 'TAG'
  id: string
  createdAt: string
  readAt?: string | null
  actor: {
    id: string
    username: string | null
    name: string | null
    avatarUrl: string | null
  }
  followRequestId?: string
  entityType?: EntityType
  entityId?: string
  contentPreview?: string
  /** For comment-like: post to navigate to */
  postEntityType?: EntityType
  postEntityId?: string
  /** For scroll-to-comment: comment id to scroll to */
  commentId?: string
  /** For COMMENT_REPLY: parent comment id (for grouping) */
  parentCommentId?: string
  /** For TAG: trip id to navigate to /trip/:tripId/thread */
  tripId?: string
}

/**
 * Creates a notification (LIKE or COMMENT) for the recipient.
 * No-op if actorId === recipientId (don't notify self).
 */
export async function createNotification(params: CreateNotificationParams) {
  const { type, actorId, recipientId, entityType, entityId, metadata } = params
  if (actorId === recipientId) {
    return null
  }

  const data = {
    type: type as NotificationType,
    actor: { connect: { id: actorId } },
    recipient: { connect: { id: recipientId } },
    ...(entityType != null && { entityType }),
    ...(entityId != null && { entityId }),
    ...(metadata != null && { metadata: metadata as Prisma.InputJsonValue })
  }

  return prisma.notification.create({ data })
}

/**
 * Returns merged notifications for the user: follow requests + like/comment.
 * Sorted by createdAt desc. Supports cursor-based pagination via before (ISO timestamp).
 */
export async function getMergedNotifications(
  recipientId: string,
  limit: number = 30,
  before?: string
): Promise<{ items: UnifiedNotificationItem[]; hasMore: boolean }> {
  const beforeDate = before ? new Date(before) : undefined
  const followWhere = beforeDate
    ? {
        followeeId: recipientId,
        status: 'PENDING' as const,
        follower: { deletedAt: null },
        createdAt: { lt: beforeDate }
      }
    : {
        followeeId: recipientId,
        status: 'PENDING' as const,
        follower: { deletedAt: null }
      }
  const notifWhere = beforeDate
    ? {
        recipientId,
        actor: { deletedAt: null },
        createdAt: { lt: beforeDate }
      }
    : {
        recipientId,
        actor: { deletedAt: null }
      }

  const [followRequests, engagementNotifications] = await Promise.all([
    prisma.followRequest.findMany({
      where: followWhere,
      include: {
        follower: {
          select: { id: true, username: true, name: true, avatarUrl: true }
        }
      },
      orderBy: { createdAt: 'desc' },
      take: limit + 1
    }),
    prisma.notification.findMany({
      where: notifWhere,
      include: {
        actor: {
          select: { id: true, username: true, name: true, avatarUrl: true }
        }
      },
      orderBy: { createdAt: 'desc' },
      take: limit + 1
    })
  ])

  type FollowReq = (typeof followRequests)[number]
  type Notif = (typeof engagementNotifications)[number]
  const followItems: UnifiedNotificationItem[] = followRequests.map((r: FollowReq) => ({
    type: 'FOLLOW_REQUEST' as const,
    id: r.id,
    createdAt: r.createdAt.toISOString(),
    actor: {
      id: r.follower.id,
      username: r.follower.username,
      name: r.follower.name,
      avatarUrl: r.follower.avatarUrl
    },
    followRequestId: r.id
  }))

  const engagementItems: UnifiedNotificationItem[] = engagementNotifications.map(
    (n: Notif) => {
      const meta = n.metadata && typeof n.metadata === 'object' ? (n.metadata as Record<string, unknown>) : null
      return {
        type: n.type as 'LIKE' | 'COMMENT' | 'COMMENT_REPLY' | 'TAG',
        id: n.id,
        createdAt: n.createdAt.toISOString(),
        readAt: n.readAt?.toISOString() ?? null,
        actor: {
          id: n.actor.id,
          username: n.actor.username,
          name: n.actor.name,
          avatarUrl: n.actor.avatarUrl
        },
        ...(n.entityType && { entityType: n.entityType }),
        ...(n.entityId && { entityId: n.entityId }),
        ...(meta?.contentPreview != null && { contentPreview: String(meta.contentPreview) }),
        ...(meta?.postEntityType != null && { postEntityType: meta.postEntityType as EntityType }),
        ...(meta?.postEntityId != null && { postEntityId: String(meta.postEntityId) }),
        ...(meta?.commentId != null && { commentId: String(meta.commentId) }),
        ...(meta?.parentCommentId != null && {
          parentCommentId: String(meta.parentCommentId),
        }),
        ...(meta?.tripId != null && { tripId: String(meta.tripId) })
      }
    }
  )

  const merged = [...followItems, ...engagementItems].sort(
    (a, b) => new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
  )
  const items = merged.slice(0, limit)
  const hasMore = merged.length > limit

  return { items, hasMore }
}

/**
 * Mark all LIKE/COMMENT notifications for the recipient as read.
 * Called when the user opens the notifications screen.
 */
export async function markAllNotificationsRead(recipientId: string): Promise<number> {
  const result = await prisma.notification.updateMany({
    where: {
      recipientId,
      readAt: null
    },
    data: { readAt: new Date() }
  })
  return result.count
}

/**
 * Mark a single notification as read. Returns false if notification not found or not owned by recipient.
 */
export async function markNotificationRead(
  notificationId: string,
  recipientId: string
): Promise<boolean> {
  const result = await prisma.notification.updateMany({
    where: {
      id: notificationId,
      recipientId,
      readAt: null
    },
    data: { readAt: new Date() }
  })
  return result.count > 0
}

/**
 * Get unread engagement notification count for badge.
 * Does not include follow requests (handled separately).
 */
export async function getUnreadNotificationCount(recipientId: string): Promise<number> {
  return prisma.notification.count({
    where: {
      recipientId,
      readAt: null,
      actor: { deletedAt: null }
    }
  })
}
