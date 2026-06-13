import type { ConversationType, Prisma } from '@prisma/client'
import { prisma } from '@/lib/prisma'
import { NotFoundError, ValidationError, AuthorizationError } from '@/lib/errors'
import { publishChatEvent, type ChatMessagePayload } from '@/lib/chat-events'

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

async function formatConversationSummary(
  conv: any,
  currentUserId: string
): Promise<ConversationSummary> {
  const myParticipant = conv.participants.find((p: any) => p.userId === currentUserId)
  const lastMsg = conv.messages[0] ?? null
  const unreadCount = myParticipant?.lastReadAt
    ? await countUnreadInConversation(conv.id, currentUserId, myParticipant.lastReadAt)
    : 0
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
    unreadCount: typeof unreadCount === 'number' ? unreadCount : 0,
    lastReadAt: myParticipant?.lastReadAt ? toISODate(myParticipant.lastReadAt) : null,
    createdAt: toISODate(conv.createdAt),
    updatedAt: toISODate(conv.updatedAt),
  }
}

async function countUnreadInConversation(
  conversationId: string,
  userId: string,
  lastReadAt: Date
): Promise<number> {
  const count = await prisma.chatMessage.count({
    where: {
      conversationId,
      senderId: { not: userId },
      createdAt: { gt: lastReadAt },
      deletedAt: null,
    },
  })
  return count
}

async function findExistingDM(userId: string, otherId: string): Promise<ConversationSummary | null> {
  const conv = await prisma.conversation.findFirst({
    where: {
      type: 'DM',
      participants: {
        every: {
          userId: { in: [userId, otherId] },
        },
      },
    },
    include: conversationListInclude,
  })
  if (!conv) return null
  const participantUserIds = conv.participants.map((p) => p.userId)
  const set = new Set(participantUserIds)
  if (set.size !== 2 || !set.has(userId) || !set.has(otherId)) return null
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
  }

  return await formatConversationSummary(conv, userId)
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

  const summaries: ConversationSummary[] = []
  for (const conv of list) {
    summaries.push(await formatConversationSummary(conv, userId))
  }
  return summaries
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
  const isParticipant = conv.participants.some((p) => p.userId === userId)
  if (!isParticipant) throw new AuthorizationError('Not a participant')
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
    select: { id: true, participants: { where: { userId }, select: { userId: true } } },
  })
  if (!conv || conv.participants.length === 0) throw new AuthorizationError('Not a participant')

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

  const participant = await prisma.conversationParticipant.findUnique({
    where: {
      conversationId_userId: { conversationId, userId },
    },
  })
  if (!participant || participant.leftAt) throw new AuthorizationError('Not a participant')

  const msg = await prisma.chatMessage.create({
    data: {
      conversationId,
      senderId: userId,
      content: content.trim() || '',
      replyToMessageId: replyToMessageId ?? null,
    },
    include: messageInclude,
  })

  if (attachmentMediaIds?.length) {
    await prisma.media.updateMany({
      where: {
        id: { in: attachmentMediaIds },
        uploadedById: userId,
        chatMessageId: null,
      },
      data: { chatMessageId: msg.id },
    })
  }

  const msgWithAttachments =
    (attachmentMediaIds?.length ?? 0) > 0
      ? await prisma.chatMessage.findUnique({
          where: { id: msg.id },
          include: messageInclude,
        })
      : msg
  const messageForPayload = msgWithAttachments ?? msg

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
  const participants = await prisma.conversationParticipant.findMany({
    where: { conversationId, leftAt: null },
    select: { userId: true },
  })
  const recipientUserIds = participants
    .map((p) => p.userId)
    .filter((id) => id !== userId)
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
  const participant = await prisma.conversationParticipant.findUnique({
    where: {
      conversationId_userId: { conversationId, userId },
    },
  })
  if (!participant || participant.leftAt) throw new AuthorizationError('Not a participant')

  const existing = await prisma.chatMessage.findUnique({
    where: { id: messageId },
    include: messageInclude,
  })
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

  const participants = await prisma.conversationParticipant.findMany({
    where: { conversationId, leftAt: null },
    select: { userId: true },
  })
  const recipientUserIds = participants
    .map((p) => p.userId)
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
  const participant = await prisma.conversationParticipant.findUnique({
    where: {
      conversationId_userId: { conversationId, userId },
    },
  })
  if (!participant || participant.leftAt) throw new AuthorizationError('Not a participant')

  const existing = await prisma.chatMessage.findUnique({
    where: { id: messageId },
    include: messageInclude,
  })
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

  const participants = await prisma.conversationParticipant.findMany({
    where: { conversationId, leftAt: null },
    select: { userId: true },
  })
  const recipientUserIds = participants.map((p) => p.userId)

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
  // Backward compatibility for clients that only handle message.new.
  publishChatEvent({
    event: 'message.new',
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
  await prisma.conversationParticipant.updateMany({
    where: { conversationId, userId },
    data: { lastReadAt: new Date() },
  })
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

  const participant = conv.participants.find((p) => p.userId === userId)
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

  const adminParticipant = conv.participants.find((p) => p.userId === adminUserId)
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

  const adminParticipant = conv.participants.find((p) => p.userId === adminUserId)
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

  const updated = await prisma.conversation.findUnique({
    where: { id: conversationId },
    include: conversationListInclude,
  })

  return await formatConversationSummary(updated!, adminUserId)
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

  const adminParticipant = conv.participants.find((p) => p.userId === adminUserId)
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
