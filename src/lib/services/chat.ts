import type { ConversationType, Prisma } from '@prisma/client'
import { v4 as uuid } from 'uuid'
import { prisma } from '@/lib/prisma'
import { NotFoundError, ValidationError, AuthorizationError } from '@/lib/errors'
import { publishChatEvent, type ChatMessagePayload } from '@/lib/chat-events'
import { LRUCache } from '@/lib/cache'

// Participant list cache — used by sendMessage, editMessage, deleteMessage,
// and the WS typing handler to avoid a DB round-trip on every hot-path call.
// TTL: 30 s (participant membership changes are infrequent).
const PARTICIPANT_CACHE_TTL_MS = 30_000
const participantCache = new LRUCache<string, string[]>(2_000)

export async function getCachedParticipantIds(conversationId: string): Promise<string[]> {
  const cached = participantCache.get(conversationId)
  if (cached !== undefined) return cached

  const rows = await prisma.conversationParticipant.findMany({
    where: { conversationId, leftAt: null },
    select: { userId: true },
  })
  const ids = rows.map((r) => r.userId)
  participantCache.set(conversationId, ids, PARTICIPANT_CACHE_TTL_MS)
  return ids
}

/** Call this after any mutation that changes conversation membership. */
export function invalidateParticipantCache(conversationId: string): void {
  participantCache.delete(conversationId)
}

const DEFAULT_PAGE_SIZE = 30
const MAX_PAGE_SIZE = 100
const MAX_CONTENT_LENGTH = 512 // Limit messages to 512 characters
const MESSAGE_EDIT_DELETE_WINDOW_MS = 15 * 60 * 1000

export type CreateConversationParams = {
  type: 'DM' | 'GROUP' | 'TRIP'
  participantIds: string[]
  name?: string | null
  tripId?: string | null
}

export type ConversationSummary = {
  id: string
  type: ConversationType
  tripId: string | null
  name: string | null
  avatarUrl: string | null
  participants: Array<{
    id: string
    userId: string
    username: string | null
    name: string | null
    avatarUrl: string | null
    role: string
    lastReadAt: string | null
  }>
  lastMessage: {
    id: string
    content: string
    senderId: string
    createdAt: string
  } | null
  unreadCount: number
  lastReadAt: string | null
  createdAt: string
  updatedAt: string
}

export type MessageWithMeta = {
  id: string
  conversationId: string
  senderId: string
  content: string
  replyToMessageId: string | null
  deletedAt: string | null
  createdAt: string
  updatedAt: string
  sender: {
    id: string
    username: string | null
    name: string | null
    avatarUrl: string | null
  }
  attachments: Array<{
    id: string
    url: string
    type: string
    publicId: string
    width: number | null
    height: number | null
    duration: number | null
  }>
  replyTo?: {
    id: string
    content: string
    senderId: string
    createdAt: string
  } | null
}

export type PaginatedMessages = {
  messages: MessageWithMeta[]
  nextCursor: string | null
  hasMore: boolean
}

function toISODate(d: Date): string {
  return d.toISOString()
}

/**
 * Create or get a DM conversation between current user and one other user.
 * For GROUP, creates a new conversation. For TRIP, use getOrCreateTripConversation.
 */
export async function createConversation(
  params: CreateConversationParams,
  userId: string
): Promise<ConversationSummary> {
  const { type, participantIds, name, tripId } = params

  if (type === 'TRIP') {
    if (!tripId) throw new ValidationError('tripId required for TRIP conversation')
    return getOrCreateTripConversation(tripId, userId)
  }

  if (type === 'DM') {
    if (participantIds.length !== 1) {
      throw new ValidationError('DM must have exactly one other participant')
    }
    const otherId = participantIds[0]
    if (otherId === userId) throw new ValidationError('Cannot create DM with yourself')
    const existing = await findExistingDM(userId, otherId)
    if (existing) return existing
    const conv = await prisma.conversation.create({
      data: {
        type: 'DM',
        participants: {
          create: [
            { userId, role: 'MEMBER' },
            { userId: otherId, role: 'MEMBER' },
          ],
        },
      },
      include: conversationListInclude,
    })
    return await formatConversationSummary(conv, userId)
  }

  // GROUP
  const allIds = Array.from(new Set([userId, ...participantIds]))
  if (allIds.length < 2) throw new ValidationError('Group must have at least 2 participants')
  if (allIds.length > 16) throw new ValidationError('Group cannot have more than 16 participants')
  const conv = await prisma.conversation.create({
    data: {
      type: 'GROUP',
      name: name ?? null,
      participants: {
        create: allIds.map((id) => ({
          userId: id,
          role: id === userId ? 'ADMIN' : 'MEMBER',
        })),
      },
    },
    include: conversationListInclude,
  })
  return await formatConversationSummary(conv, userId)
}

const conversationListInclude = {
  participants: {
    include: {
      user: {
        select: {
          id: true,
          username: true,
          name: true,
          avatarUrl: true,
        },
      },
    },
  },
  messages: {
    orderBy: { createdAt: 'desc' as const },
    take: 1,
    select: {
      id: true,
      content: true,
      senderId: true,
      createdAt: true,
    },
  },
} satisfies Prisma.ConversationInclude

/**
 * Synchronously formats a single conversation summary.
 * Requires the caller to pre-compute the unreadCount via batchFetchUnreadCounts.
 */
function formatConversationSummarySync(
  conv: any,
  currentUserId: string,
  unreadCount: number
): ConversationSummary {
  const myParticipant = conv.participants.find((p: any) => p.userId === currentUserId)
  const lastMsg = conv.messages[0] ?? null
  return {
    id: conv.id,
    type: conv.type,
    tripId: conv.tripId ?? null,
    name: conv.name ?? null,
    avatarUrl: conv.avatarUrl ?? null,
    participants: conv.participants
      .filter((p: any) => !p.leftAt)
      .map((p: any) => ({
        id: p.id,
        userId: p.userId,
        username: p.user.username,
        name: p.user.name,
        avatarUrl: p.user.avatarUrl,
        role: p.role,
        lastReadAt: p.lastReadAt ? toISODate(p.lastReadAt) : null,
      })),
    lastMessage: lastMsg
      ? {
          id: lastMsg.id,
          content: lastMsg.content,
          senderId: lastMsg.senderId,
          createdAt: toISODate(lastMsg.createdAt),
        }
      : null,
    unreadCount,
    lastReadAt: myParticipant?.lastReadAt ? toISODate(myParticipant.lastReadAt) : null,
    createdAt: toISODate(conv.createdAt),
    updatedAt: toISODate(conv.updatedAt),
  }
}

/**
 * Async wrapper for single-conversation use (e.g. getConversation, participant mutations).
 * Falls back to a direct COUNT rather than a batch query since only 1 conversation is involved.
 */
async function formatConversationSummary(
  conv: any,
  currentUserId: string
): Promise<ConversationSummary> {
  const myParticipant = conv.participants.find((p: any) => p.userId === currentUserId)
  let unreadCount = 0
  if (myParticipant) {
    if (myParticipant.lastReadAt) {
      unreadCount = await prisma.chatMessage.count({
        where: {
          conversationId: conv.id,
          senderId: { not: currentUserId },
          createdAt: { gt: myParticipant.lastReadAt },
          deletedAt: null,
        },
      })
    } else {
      unreadCount = await prisma.chatMessage.count({
        where: {
          conversationId: conv.id,
          senderId: { not: currentUserId },
          deletedAt: null,
        },
      })
    }
  }
  return formatConversationSummarySync(conv, currentUserId, unreadCount)
}

/**
 * Fetches all unread counts for a set of conversations in ONE SQL query,
 * replacing the previous N+1 pattern (one COUNT per conversation).
 *
 * Returns a Map<conversationId, unreadCount>.
 */
async function batchFetchUnreadCounts(
  conversationIds: string[],
  userId: string,
  participantsByConvId: Map<string, { lastReadAt: Date | null }>
): Promise<Map<string, number>> {
  if (conversationIds.length === 0) return new Map()

  type UnreadRow = { conversation_id: string; unread_count: bigint }
  const rows = await prisma.$queryRaw<UnreadRow[]>`
    SELECT
      m.conversation_id,
      COUNT(m.id)::bigint AS unread_count
    FROM chat_messages m
    JOIN conversation_participants cp
      ON cp.conversation_id = m.conversation_id
     AND cp.user_id = ${userId}::uuid
     AND cp.left_at IS NULL
    WHERE m.conversation_id = ANY(${conversationIds}::uuid[])
      AND m.sender_id != ${userId}::uuid
      AND m.deleted_at IS NULL
      AND (
        cp.last_read_at IS NULL
        OR m.created_at > cp.last_read_at
      )
    GROUP BY m.conversation_id
  `

  const result = new Map<string, number>()
  for (const row of rows) {
    result.set(row.conversation_id, Number(row.unread_count))
  }
  return result
}

async function touchConversation(conversationId: string): Promise<void> {
  await prisma.conversation.update({
    where: { id: conversationId },
    data: { updatedAt: new Date() },
  })
}

async function findExistingDM(userId: string, otherId: string): Promise<ConversationSummary | null> {
  const conv = await prisma.conversation.findFirst({
    where: {
      type: 'DM',
      AND: [
        { participants: { some: { userId, leftAt: null } } },
        { participants: { some: { userId: otherId, leftAt: null } } },
      ],
    },
    include: conversationListInclude,
  })
  if (!conv) return null
  const activeParticipants = conv.participants.filter((p) => !p.leftAt)
  if (activeParticipants.length !== 2) return null
  const activeUserIds = new Set(activeParticipants.map((p) => p.userId))
  if (!activeUserIds.has(userId) || !activeUserIds.has(otherId)) return null
  return await formatConversationSummary(conv, userId)
}

/**
 * Get or create the TRIP-scoped conversation for a trip (participants = TripParticipant set).
 */
export async function getOrCreateTripConversation(
  tripId: string,
  userId: string
): Promise<ConversationSummary> {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: { id: true, participants: { select: { userId: true } } },
  })
  if (!trip) throw new NotFoundError('Trip not found')

  const isParticipant = trip.participants.some((p) => p.userId === userId)
  if (!isParticipant) throw new AuthorizationError('Not a participant of this trip')

  let conv = await prisma.conversation.findUnique({
    where: { tripId },
    include: conversationListInclude,
  })

  if (!conv) {
    conv = await prisma.conversation.create({
      data: {
        type: 'TRIP',
        tripId,
        participants: {
          create: trip.participants.map((p) => ({
            userId: p.userId,
            role: 'MEMBER',
          })),
        },
      },
      include: conversationListInclude,
    })
  } else {
    await syncTripConversationParticipants(conv, trip.participants.map((p) => p.userId))
    conv = await prisma.conversation.findUnique({
      where: { tripId },
      include: conversationListInclude,
    })
    if (!conv) throw new NotFoundError('Conversation not found')
  }

  return await formatConversationSummary(conv, userId)
}

async function syncTripConversationParticipants(
  conv: { id: string; participants: Array<{ id: string; userId: string; leftAt: Date | null }> },
  tripUserIds: string[]
): Promise<void> {
  const tripUserIdSet = new Set(tripUserIds)
  const conversationId = conv.id

  // 1. Add brand-new members in one batch insert.
  const existingUserIds = new Set(conv.participants.map((p) => p.userId))
  const newMemberIds = tripUserIds.filter((id) => !existingUserIds.has(id))
  if (newMemberIds.length > 0) {
    await prisma.conversationParticipant.createMany({
      data: newMemberIds.map((userId) => ({
        conversationId,
        userId,
        role: 'MEMBER' as const,
      })),
      skipDuplicates: true,
    })
  }

  // 2. Re-join previously-departed members in one batch update.
  const rejoinIds = conv.participants
    .filter((p) => tripUserIdSet.has(p.userId) && p.leftAt !== null)
    .map((p) => p.id)
  if (rejoinIds.length > 0) {
    await prisma.conversationParticipant.updateMany({
      where: { id: { in: rejoinIds } },
      data: { leftAt: null, joinedAt: new Date() },
    })
  }

  // 3. Soft-remove participants no longer in the trip in one batch update.
  const departedIds = conv.participants
    .filter((p) => !tripUserIdSet.has(p.userId) && p.leftAt === null)
    .map((p) => p.id)
  if (departedIds.length > 0) {
    await prisma.conversationParticipant.updateMany({
      where: { id: { in: departedIds } },
      data: { leftAt: new Date() },
    })
  }

  // Any membership change invalidates the participant cache for this conversation.
  if (newMemberIds.length > 0 || rejoinIds.length > 0 || departedIds.length > 0) {
    invalidateParticipantCache(conversationId)
  }
}

export async function listConversations(
  userId: string,
  options?: { tripId?: string }
): Promise<ConversationSummary[]> {
  const where: Prisma.ConversationWhereInput = {
    participants: {
      some: { userId, leftAt: null },
    },
  }
  if (options?.tripId) where.tripId = options.tripId

  const list = await prisma.conversation.findMany({
    where,
    orderBy: { updatedAt: 'desc' },
    include: conversationListInclude,
  })

  if (list.length === 0) return []

  // Build a map of conversationId → participant's lastReadAt for the batch query.
  const participantsByConvId = new Map<string, { lastReadAt: Date | null }>()
  for (const conv of list) {
    const mine = conv.participants.find((p: any) => p.userId === userId)
    participantsByConvId.set(conv.id, { lastReadAt: mine?.lastReadAt ?? null })
  }

  // Fetch all unread counts in ONE query instead of N COUNT queries.
  const conversationIds = list.map((c) => c.id)
  const unreadMap = await batchFetchUnreadCounts(conversationIds, userId, participantsByConvId)

  return list.map((conv) =>
    formatConversationSummarySync(conv, userId, unreadMap.get(conv.id) ?? 0)
  )
}

export async function getConversation(
  conversationId: string,
  userId: string
): Promise<ConversationSummary> {
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })
  if (!conv) throw new NotFoundError('Conversation not found')
  const isActiveParticipant = conv.participants.some(
    (p) => p.userId === userId && !p.leftAt
  )
  if (!isActiveParticipant) throw new AuthorizationError('Not a participant')
  return await formatConversationSummary(conv, userId)
}

export async function getMessages(
  conversationId: string,
  userId: string,
  options: { limit?: number; before?: string } = {}
): Promise<PaginatedMessages> {
  const limit = Math.min(
    Math.max(options.limit ?? DEFAULT_PAGE_SIZE, 1),
    MAX_PAGE_SIZE
  )

  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    select: {
      id: true,
      participants: {
        where: { userId, leftAt: null },
        select: { userId: true },
      },
    },
  })
  if (!conv || conv.participants.length === 0) throw new AuthorizationError('Not a participant')

  if (options.before) {
    const cursorMsg = await prisma.chatMessage.findUnique({
      where: { id: options.before },
      select: { conversationId: true },
    })
    if (!cursorMsg || cursorMsg.conversationId !== conversationId) {
      throw new ValidationError('Invalid message cursor')
    }
  }

  const cursorCondition: Prisma.ChatMessageWhereUniqueInput | undefined = options.before
    ? { id: options.before }
    : undefined

  const messages = await prisma.chatMessage.findMany({
    // Keep deleted messages in history so clients can render "This message was deleted".
    where: { conversationId },
    orderBy: { createdAt: 'desc' },
    take: limit + 1,
    ...(cursorCondition && { cursor: cursorCondition, skip: 1 }),
    include: messageInclude,
  })

  const hasMore = messages.length > limit
  const slice = hasMore ? messages.slice(0, limit) : messages
  const nextCursor = hasMore && slice.length > 0 ? slice[slice.length - 1].id : null

  const formatted: MessageWithMeta[] = slice.map((m) => ({
    id: m.id,
    conversationId: m.conversationId,
    senderId: m.senderId,
    content: m.content,
    replyToMessageId: m.replyToMessageId,
    deletedAt: m.deletedAt ? toISODate(m.deletedAt) : null,
    createdAt: toISODate(m.createdAt),
    updatedAt: toISODate(m.updatedAt),
    sender: {
      id: m.sender.id,
      username: m.sender.username,
      name: m.sender.name,
      avatarUrl: m.sender.avatarUrl,
    },
    attachments: m.attachments.map((a) => ({
      id: a.id,
      url: a.url,
      type: a.type,
      publicId: a.publicId,
      width: a.width,
      height: a.height,
      duration: a.duration,
    })),
    replyTo: m.replyTo
      ? {
          id: m.replyTo.id,
          content: m.replyTo.content,
          senderId: m.replyTo.senderId,
          createdAt: toISODate(m.replyTo.createdAt),
        }
      : undefined,
  }))

  return {
    messages: formatted,
    nextCursor,
    hasMore: !!hasMore,
  }
}

const messageInclude = {
  sender: {
    select: {
      id: true,
      username: true,
      name: true,
      avatarUrl: true,
    },
  },
  attachments: {
    select: {
      id: true,
      url: true,
      type: true,
      publicId: true,
      width: true,
      height: true,
      duration: true,
    },
  },
  replyTo: {
    select: {
      id: true,
      content: true,
      senderId: true,
      createdAt: true,
    },
  },
} satisfies Prisma.ChatMessageInclude

export type SendMessageParams = {
  content: string
  replyToMessageId?: string | null
  attachmentMediaIds?: string[]
}

function ensureWithinEditDeleteWindow(createdAt: Date): void {
  const ageMs = Date.now() - createdAt.getTime()
  if (ageMs > MESSAGE_EDIT_DELETE_WINDOW_MS) {
    throw new ValidationError('Messages can only be edited or deleted within 15 minutes')
  }
}

export async function sendMessage(
  conversationId: string,
  userId: string,
  params: SendMessageParams
): Promise<MessageWithMeta> {
  const { content, replyToMessageId, attachmentMediaIds } = params

  if (!content.trim() && (!attachmentMediaIds || attachmentMediaIds.length === 0)) {
    throw new ValidationError('Message must have content or at least one attachment')
  }
  if (content.length > MAX_CONTENT_LENGTH) {
    throw new ValidationError('Message content too long')
  }

  // 1. Parallel: auth check + reply target validation (independent DB reads).
  const [participant, replyTarget] = await Promise.all([
    prisma.conversationParticipant.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    }),
    replyToMessageId
      ? prisma.chatMessage.findUnique({
          where: { id: replyToMessageId },
          select: { conversationId: true, deletedAt: true },
        })
      : Promise.resolve(null),
  ])

  if (!participant || participant.leftAt) throw new AuthorizationError('Not a participant')
  if (replyToMessageId) {
    if (
      !replyTarget ||
      replyTarget.conversationId !== conversationId ||
      replyTarget.deletedAt != null
    ) {
      throw new ValidationError('Invalid reply target message')
    }
  }

  // 2. Pre-generate the message ID so we can link media in the same transaction
  //    without a second SELECT (eliminates the re-fetch step for attachments).
  const messageId = uuid()
  const trimmedContent = content.trim()

  const messageForPayload = await prisma.$transaction(async (tx) => {
    const created = await tx.chatMessage.create({
      data: {
        id: messageId,
        conversationId,
        senderId: userId,
        content: trimmedContent,
        replyToMessageId: replyToMessageId ?? null,
      },
    })
    if (attachmentMediaIds?.length) {
      await tx.media.updateMany({
        where: {
          id: { in: attachmentMediaIds },
          uploadedById: userId,
          chatMessageId: null,
        },
        data: { chatMessageId: created.id },
      })
    }
    // Fetch once inside the transaction to get fully resolved relations.
    return tx.chatMessage.findUnique({
      where: { id: created.id },
      include: messageInclude,
    })
  })

  if (!messageForPayload) throw new ValidationError('Message creation failed unexpectedly')

  // 3. Touch the conversation timestamp in the background — it only affects sort
  //    order and does not need to block the response.
  touchConversation(conversationId).catch(console.error)

  // 4. Resolve recipient list from cache (avoids an extra DB round-trip).
  const recipientUserIds = await getCachedParticipantIds(conversationId)

  const payload: ChatMessagePayload = {
    id: messageForPayload.id,
    conversationId: messageForPayload.conversationId,
    senderId: messageForPayload.senderId,
    content: messageForPayload.content,
    replyToMessageId: messageForPayload.replyToMessageId,
    createdAt: toISODate(messageForPayload.createdAt),
    updatedAt: toISODate(messageForPayload.updatedAt),
    attachments: messageForPayload.attachments.map((a) => ({
      id: a.id,
      url: a.url,
      type: a.type,
      publicId: a.publicId,
    })),
    sender: {
      id: messageForPayload.sender.id,
      username: messageForPayload.sender.username,
      name: messageForPayload.sender.name,
      avatarUrl: messageForPayload.sender.avatarUrl,
    },
    replyTo: messageForPayload.replyTo
      ? {
          id: messageForPayload.replyTo.id,
          content: messageForPayload.replyTo.content,
          senderId: messageForPayload.replyTo.senderId,
          createdAt: toISODate(messageForPayload.replyTo.createdAt),
        }
      : null,
  }
  publishChatEvent({
    event: 'message.new',
    conversationId,
    message: payload,
    recipientUserIds,
  })

  return {
    id: messageForPayload.id,
    conversationId: messageForPayload.conversationId,
    senderId: messageForPayload.senderId,
    content: messageForPayload.content,
    replyToMessageId: messageForPayload.replyToMessageId,
    deletedAt: null,
    createdAt: toISODate(messageForPayload.createdAt),
    updatedAt: toISODate(messageForPayload.updatedAt),
    sender: {
      id: messageForPayload.sender.id,
      username: messageForPayload.sender.username,
      name: messageForPayload.sender.name,
      avatarUrl: messageForPayload.sender.avatarUrl,
    },
    attachments: messageForPayload.attachments.map((a) => ({
      id: a.id,
      url: a.url,
      type: a.type,
      publicId: a.publicId,
      width: a.width,
      height: a.height,
      duration: a.duration,
    })),
    replyTo: messageForPayload.replyTo
      ? {
          id: messageForPayload.replyTo.id,
          content: messageForPayload.replyTo.content,
          senderId: messageForPayload.replyTo.senderId,
          createdAt: toISODate(messageForPayload.replyTo.createdAt),
        }
      : undefined,
  }
}

export async function deleteMessage(
  conversationId: string,
  messageId: string,
  userId: string
): Promise<MessageWithMeta> {
  // Parallel: auth check + message fetch (independent reads).
  const [participant, existing] = await Promise.all([
    prisma.conversationParticipant.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    }),
    prisma.chatMessage.findUnique({
      where: { id: messageId },
      include: messageInclude,
    }),
  ])

  if (!participant || participant.leftAt) throw new AuthorizationError('Not a participant')
  if (!existing || existing.conversationId !== conversationId) {
    throw new NotFoundError('Message not found')
  }
  if (existing.senderId !== userId) {
    throw new AuthorizationError('You can only delete your own messages')
  }
  if (existing.deletedAt != null) {
    throw new ValidationError('Message is already deleted')
  }
  ensureWithinEditDeleteWindow(existing.createdAt)

  const deleted =
    existing.deletedAt != null
      ? existing
      : await prisma.chatMessage.update({
          where: { id: messageId },
          data: {
            deletedAt: new Date(),
            content: '',
          },
          include: messageInclude,
        })

  touchConversation(conversationId).catch(console.error)

  // Exclude the deleter: their local state is already updated via the REST response.
  const allParticipantIds = await getCachedParticipantIds(conversationId)
  const recipientUserIds = allParticipantIds.filter((id) => id !== userId)
  publishChatEvent({
    event: 'message.deleted',
    conversationId,
    messageId: deleted.id,
    deletedAt: toISODate(deleted.deletedAt ?? new Date()),
    recipientUserIds,
  })

  return {
    id: deleted.id,
    conversationId: deleted.conversationId,
    senderId: deleted.senderId,
    content: deleted.content,
    replyToMessageId: deleted.replyToMessageId,
    deletedAt: deleted.deletedAt ? toISODate(deleted.deletedAt) : null,
    createdAt: toISODate(deleted.createdAt),
    updatedAt: toISODate(deleted.updatedAt),
    sender: {
      id: deleted.sender.id,
      username: deleted.sender.username,
      name: deleted.sender.name,
      avatarUrl: deleted.sender.avatarUrl,
    },
    attachments: deleted.attachments.map((a) => ({
      id: a.id,
      url: a.url,
      type: a.type,
      publicId: a.publicId,
      width: a.width,
      height: a.height,
      duration: a.duration,
    })),
    replyTo: deleted.replyTo
      ? {
          id: deleted.replyTo.id,
          content: deleted.replyTo.content,
          senderId: deleted.replyTo.senderId,
          createdAt: toISODate(deleted.replyTo.createdAt),
        }
      : undefined,
  }
}

export async function editMessage(
  conversationId: string,
  messageId: string,
  userId: string,
  content: string
): Promise<MessageWithMeta> {
  // Parallel: auth check + message fetch (independent reads).
  const [participant, existing] = await Promise.all([
    prisma.conversationParticipant.findUnique({
      where: { conversationId_userId: { conversationId, userId } },
    }),
    prisma.chatMessage.findUnique({
      where: { id: messageId },
      include: messageInclude,
    }),
  ])

  if (!participant || participant.leftAt) throw new AuthorizationError('Not a participant')
  if (!existing || existing.conversationId !== conversationId) {
    throw new NotFoundError('Message not found')
  }
  if (existing.senderId !== userId) {
    throw new AuthorizationError('You can only edit your own messages')
  }
  if (existing.deletedAt != null) {
    throw new ValidationError('Deleted messages cannot be edited')
  }
  ensureWithinEditDeleteWindow(existing.createdAt)

  const trimmed = content.trim()
  if (!trimmed) {
    throw new ValidationError('Message content cannot be empty')
  }
  if (trimmed.length > MAX_CONTENT_LENGTH) {
    throw new ValidationError('Message content too long')
  }

  const updated = await prisma.chatMessage.update({
    where: { id: messageId },
    data: { content: trimmed },
    include: messageInclude,
  })

  touchConversation(conversationId).catch(console.error)

  const recipientUserIds = await getCachedParticipantIds(conversationId)

  const payload: ChatMessagePayload = {
    id: updated.id,
    conversationId: updated.conversationId,
    senderId: updated.senderId,
    content: updated.content,
    replyToMessageId: updated.replyToMessageId,
    createdAt: toISODate(updated.createdAt),
    updatedAt: toISODate(updated.updatedAt),
    attachments: updated.attachments.map((a) => ({
      id: a.id,
      url: a.url,
      type: a.type,
      publicId: a.publicId,
    })),
    sender: {
      id: updated.sender.id,
      username: updated.sender.username,
      name: updated.sender.name,
      avatarUrl: updated.sender.avatarUrl,
    },
    replyTo: updated.replyTo
      ? {
          id: updated.replyTo.id,
          content: updated.replyTo.content,
          senderId: updated.replyTo.senderId,
          createdAt: toISODate(updated.replyTo.createdAt),
        }
      : null,
  }

  publishChatEvent({
    event: 'message.updated',
    conversationId,
    message: payload,
    recipientUserIds,
  })

  return {
    id: updated.id,
    conversationId: updated.conversationId,
    senderId: updated.senderId,
    content: updated.content,
    replyToMessageId: updated.replyToMessageId,
    deletedAt: updated.deletedAt ? toISODate(updated.deletedAt) : null,
    createdAt: toISODate(updated.createdAt),
    updatedAt: toISODate(updated.updatedAt),
    sender: {
      id: updated.sender.id,
      username: updated.sender.username,
      name: updated.sender.name,
      avatarUrl: updated.sender.avatarUrl,
    },
    attachments: updated.attachments.map((a) => ({
      id: a.id,
      url: a.url,
      type: a.type,
      publicId: a.publicId,
      width: a.width,
      height: a.height,
      duration: a.duration,
    })),
    replyTo: updated.replyTo
      ? {
          id: updated.replyTo.id,
          content: updated.replyTo.content,
          senderId: updated.replyTo.senderId,
          createdAt: toISODate(updated.replyTo.createdAt),
        }
      : undefined,
  }
}

export async function markConversationRead(
  conversationId: string,
  userId: string
): Promise<void> {
  const participant = await prisma.conversationParticipant.findUnique({
    where: {
      conversationId_userId: { conversationId, userId },
    },
  })
  if (!participant || participant.leftAt) return

  const lastReadAt = new Date()
  await prisma.conversationParticipant.update({
    where: { id: participant.id },
    data: { lastReadAt },
  })

  // Notify other participants in real-time so senders can show "Seen".
  const allParticipantIds = await getCachedParticipantIds(conversationId)
  const recipientUserIds = allParticipantIds.filter((id) => id !== userId)
  if (recipientUserIds.length > 0) {
    publishChatEvent({
      event: 'conversation.read',
      conversationId,
      userId,
      lastReadAt: lastReadAt.toISOString(),
      recipientUserIds,
    })
  }
}

export async function updateGroupDetails(
  conversationId: string,
  userId: string,
  data: { name?: string | null; avatarUrl?: string | null }
): Promise<ConversationSummary> {
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  if (!conv) throw new NotFoundError('Group not found')
  if (conv.type !== 'GROUP') throw new ValidationError('Only groups details can be edited')

  const participant = conv.participants.find((p) => p.userId === userId && !p.leftAt)
  if (!participant) throw new AuthorizationError('Not a participant')
  if (participant.role !== 'ADMIN') throw new AuthorizationError('Only admins can update group details')

  const updated = await prisma.conversation.update({
    where: { id: conversationId },
    data: {
      ...(data.name !== undefined && { name: data.name }),
      ...(data.avatarUrl !== undefined && { avatarUrl: data.avatarUrl }),
    },
    include: conversationListInclude,
  })

  return await formatConversationSummary(updated, userId)
}

export async function addGroupParticipant(
  conversationId: string,
  adminUserId: string,
  targetUserId: string
): Promise<ConversationSummary> {
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  if (!conv) throw new NotFoundError('Group not found')
  if (conv.type !== 'GROUP') throw new ValidationError('Only group participants can be managed')

  const adminParticipant = conv.participants.find((p) => p.userId === adminUserId && !p.leftAt)
  if (!adminParticipant) throw new AuthorizationError('Not a participant')
  if (adminParticipant.role !== 'ADMIN') throw new AuthorizationError('Only admins can add participants')

  const existing = conv.participants.find((p) => p.userId === targetUserId)
  if (existing && !existing.leftAt) {
    throw new ValidationError('User is already a participant')
  }

  // 16-member limit check (active participants)
  const activeCount = conv.participants.filter(p => !p.leftAt).length
  if (activeCount >= 16) {
    throw new ValidationError('Group has reached the maximum of 16 participants')
  }

  if (existing && existing.leftAt) {
    await prisma.conversationParticipant.update({
      where: { id: existing.id },
      data: { leftAt: null, joinedAt: new Date(), role: 'MEMBER' },
    })
  } else {
    await prisma.conversationParticipant.create({
      data: {
        conversationId,
        userId: targetUserId,
        role: 'MEMBER',
      },
    })
  }

  invalidateParticipantCache(conversationId)

  const updated = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  return await formatConversationSummary(updated!, adminUserId)
}

export async function removeGroupParticipant(
  conversationId: string,
  adminUserId: string,
  targetUserId: string
): Promise<ConversationSummary> {
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  if (!conv) throw new NotFoundError('Group not found')
  if (conv.type !== 'GROUP') throw new ValidationError('Only group participants can be managed')

  const adminParticipant = conv.participants.find((p) => p.userId === adminUserId && !p.leftAt)
  if (!adminParticipant) throw new AuthorizationError('Not a participant')
  if (adminParticipant.role !== 'ADMIN') throw new AuthorizationError('Only admins can remove participants')

  const targetParticipant = conv.participants.find((p) => p.userId === targetUserId)
  if (!targetParticipant || targetParticipant.leftAt) {
    throw new ValidationError('User is not a participant')
  }

  if (targetUserId === adminUserId) {
    throw new ValidationError('Admins cannot remove themselves')
  }

  await prisma.conversationParticipant.update({
    where: { id: targetParticipant.id },
    data: { leftAt: new Date() },
  })

  invalidateParticipantCache(conversationId)

  const updated = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  return await formatConversationSummary(updated!, adminUserId)
}

/**
 * Allows any active participant to voluntarily leave a GROUP conversation.
 * Blocked if the user is the sole remaining admin and other members exist —
 * they must promote another member to admin first.
 */
export async function leaveGroup(
  conversationId: string,
  userId: string
): Promise<void> {
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  if (!conv) throw new NotFoundError('Conversation not found')
  if (conv.type !== 'GROUP') {
    throw new ValidationError('Use the trip leave endpoint to leave a TRIP conversation')
  }

  const activeParticipants = conv.participants.filter((p) => !p.leftAt)
  const participant = activeParticipants.find((p) => p.userId === userId)
  if (!participant) throw new AuthorizationError('Not an active participant')

  // Block the sole admin from leaving if other members would be left admin-less.
  const activeAdmins = activeParticipants.filter((p) => p.role === 'ADMIN')
  const isOnlyAdmin = participant.role === 'ADMIN' && activeAdmins.length === 1
  const hasOtherMembers = activeParticipants.length > 1
  if (isOnlyAdmin && hasOtherMembers) {
    throw new ValidationError(
      'You are the only admin. Promote another member to admin before leaving.'
    )
  }

  await prisma.conversationParticipant.update({
    where: { id: participant.id },
    data: { leftAt: new Date() },
  })

  invalidateParticipantCache(conversationId)
}

export async function promoteToAdmin(
  conversationId: string,
  adminUserId: string,
  targetUserId: string
): Promise<ConversationSummary> {
  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  if (!conv) throw new NotFoundError('Group not found')
  if (conv.type !== 'GROUP') throw new ValidationError('Only group participants can be managed')

  const adminParticipant = conv.participants.find((p) => p.userId === adminUserId && !p.leftAt)
  if (!adminParticipant) throw new AuthorizationError('Not a participant')
  if (adminParticipant.role !== 'ADMIN') throw new AuthorizationError('Only admins can promote users')

  const targetParticipant = conv.participants.find((p) => p.userId === targetUserId)
  if (!targetParticipant || targetParticipant.leftAt) {
    throw new ValidationError('User is not a participant')
  }

  if (targetParticipant.role === 'ADMIN') {
    throw new ValidationError('User is already an admin')
  }

  await prisma.conversationParticipant.update({
    where: { id: targetParticipant.id },
    data: { role: 'ADMIN' },
  })

  const updated = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  return await formatConversationSummary(updated!, adminUserId)
}
