import type { EntityType, NotificationType, Prisma } from '@prisma/client'
import { prisma } from '../prisma'

export type CreateNotificationParams = {
  type: 'LIKE' | 'COMMENT_LIKE' | 'COMMENT' | 'COMMENT_REPLY' | 'TAG'
  actorId: string
  recipientId: string
  entityType?: EntityType
  entityId?: string
  metadata?: Record<string, unknown>
}

export type UnifiedNotificationItem = {
  type: 'FOLLOW_REQUEST' | 'LIKE' | 'COMMENT_LIKE' | 'COMMENT' | 'COMMENT_REPLY' | 'TAG'
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
  /** For thread navigation highlight */
  threadEntryId?: string
}

type CursorSource = 'FOLLOW_REQUEST' | 'NOTIFICATION'
type MergedCursor = {
  v: 1
  createdAt: string
  id: string
  source: CursorSource
}
type MergedNotificationItem = UnifiedNotificationItem & {
  _cursorSource: CursorSource
}

function getSourceRank(source: CursorSource): number {
  // Notification events come after follow requests for identical timestamps.
  return source === 'NOTIFICATION' ? 1 : 0
}

function toBase64Url(input: string): string {
  return Buffer.from(input, 'utf8')
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/g, '')
}

function fromBase64Url(input: string): string {
  const normalized = input.replace(/-/g, '+').replace(/_/g, '/')
  const padLength = (4 - (normalized.length % 4)) % 4
  const padded = normalized + '='.repeat(padLength)
  return Buffer.from(padded, 'base64').toString('utf8')
}

function encodeCursor(item: MergedNotificationItem): string {
  const payload: MergedCursor = {
    v: 1,
    createdAt: item.createdAt,
    source: item._cursorSource,
    id: item.id,
  }
  return toBase64Url(JSON.stringify(payload))
}

function parseCursor(cursor?: string): MergedCursor | null {
  if (!cursor) return null
  try {
    const decoded = fromBase64Url(cursor)
    const parsed = JSON.parse(decoded) as Partial<MergedCursor>
    if (
      parsed.v === 1 &&
      typeof parsed.createdAt === 'string' &&
      typeof parsed.id === 'string' &&
      (parsed.source === 'FOLLOW_REQUEST' || parsed.source === 'NOTIFICATION')
    ) {
      return {
        v: 1,
        createdAt: parsed.createdAt,
        id: parsed.id,
        source: parsed.source,
      }
    }
  } catch (error) {
    // Log invalid cursor in all environments (can indicate client bugs or malicious requests)
    // Use error level in production, warn in development for visibility
    const logLevel = process.env.NODE_ENV === 'development' ? console.warn : console.error
    logLevel('[Notification] Invalid cursor format - falling back to first page', {
      cursorLength: cursor.length,
      error: error instanceof Error ? error.message : 'Parse failed',
      // Only log cursor preview in development (privacy/security concern in production)
      ...(process.env.NODE_ENV === 'development' && { cursorPreview: cursor.substring(0, 30) + '...' }),
    })
    return null
  }
  // Validation failed (wrong version or missing fields)
  const logLevel = process.env.NODE_ENV === 'development' ? console.warn : console.error
  logLevel('[Notification] Cursor validation failed - falling back to first page', {
    cursorLength: cursor.length,
    // Only log cursor preview in development
    ...(process.env.NODE_ENV === 'development' && { cursorPreview: cursor.substring(0, 30) + '...' }),
  })
  return null
}

function isStrictlyOlderThanCursor(item: MergedNotificationItem, cursor: MergedCursor): boolean {
  const itemTime = new Date(item.createdAt).getTime()
  const cursorTime = new Date(cursor.createdAt).getTime()
  if (itemTime !== cursorTime) {
    return itemTime < cursorTime
  }
  const itemRank = getSourceRank(item._cursorSource)
  const cursorRank = getSourceRank(cursor.source)
  if (itemRank !== cursorRank) {
    return itemRank < cursorRank
  }
  return item.id < cursor.id
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
 * Sorted by createdAt desc. Supports cursor-based pagination via opaque `before` token.
 */
// Multiplier for fetching items per source when using strict cursor pagination.
// We fetch more than `limit` because:
// 1. We merge two sources (follow requests + notifications) which may have different distributions
// 2. After merging and sorting, we filter to items strictly older than cursor
// 3. This ensures we have enough items to fill the requested page size
// Tune based on production metrics if merge ratio differs significantly from 1:1
const STRICT_CURSOR_FETCH_MULTIPLIER = 3
const MIN_FETCH_PER_SOURCE = 50

export async function getMergedNotifications(
  recipientId: string,
  limit: number = 30,
  before?: string
): Promise<{ items: UnifiedNotificationItem[]; hasMore: boolean; nextCursor?: string }> {
  const parsedCursor = parseCursor(before)
  const beforeDate = parsedCursor ? new Date(parsedCursor.createdAt) : undefined
  const useStrictCursor = !!parsedCursor
  const takePerSource = useStrictCursor
    ? Math.max(limit * STRICT_CURSOR_FETCH_MULTIPLIER, MIN_FETCH_PER_SOURCE)
    : limit + 1
  const followWhere = beforeDate
    ? {
      followeeId: recipientId,
      status: 'PENDING' as const,
      follower: { deletedAt: null },
      createdAt: { [useStrictCursor ? 'lte' : 'lt']: beforeDate }
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
      createdAt: { [useStrictCursor ? 'lte' : 'lt']: beforeDate }
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
      take: takePerSource
    }),
    prisma.notification.findMany({
      where: notifWhere,
      include: {
        actor: {
          select: { id: true, username: true, name: true, avatarUrl: true }
        }
      },
      orderBy: { createdAt: 'desc' },
      take: takePerSource
    })
  ])

  type FollowReq = (typeof followRequests)[number]
  type Notif = (typeof engagementNotifications)[number]
  const followItems: MergedNotificationItem[] = followRequests.map((r: FollowReq) => ({
    type: 'FOLLOW_REQUEST' as const,
    id: r.id,
    createdAt: r.createdAt.toISOString(),
    actor: {
      id: r.follower.id,
      username: r.follower.username,
      name: r.follower.name,
      avatarUrl: r.follower.avatarUrl
    },
    followRequestId: r.id,
    _cursorSource: 'FOLLOW_REQUEST',
  }))

  const engagementItems: MergedNotificationItem[] = engagementNotifications.map(
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
        ...(meta?.tripId != null && { tripId: String(meta.tripId) }),
        ...(meta?.threadEntryId != null && {
          threadEntryId: String(meta.threadEntryId),
        }),
        _cursorSource: 'NOTIFICATION' as const,
      }
    }
  )

  const merged = [...followItems, ...engagementItems].sort((a, b) => {
    const timeDiff = new Date(b.createdAt).getTime() - new Date(a.createdAt).getTime()
    if (timeDiff !== 0) return timeDiff
    const rankDiff = getSourceRank(b._cursorSource) - getSourceRank(a._cursorSource)
    if (rankDiff !== 0) return rankDiff
    return b.id.localeCompare(a.id)
  })

  const filtered = parsedCursor
    ? merged.filter((item) => isStrictlyOlderThanCursor(item, parsedCursor))
    : merged

  const pageItems = filtered.slice(0, limit)
  const hasMore = filtered.length > limit
  const nextCursor =
    pageItems.length > 0 ? encodeCursor(pageItems[pageItems.length - 1]) : undefined
  const items: UnifiedNotificationItem[] = pageItems.map(({ _cursorSource, ...rest }) => rest)

  return { items, hasMore, nextCursor }
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
): Promise<'marked' | 'already_read' | 'not_found'> {
  const existing = await prisma.notification.findUnique({
    where: { id: notificationId },
    select: { recipientId: true, readAt: true },
  })
  if (!existing || existing.recipientId !== recipientId) {
    return 'not_found'
  }
  if (existing.readAt != null) {
    return 'already_read'
  }
  await prisma.notification.update({
    where: { id: notificationId },
    data: { readAt: new Date() },
  })
  return 'marked'
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
