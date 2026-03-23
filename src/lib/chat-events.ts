/**
 * In-process event bus for chat real-time events.
 * Used by REST handlers to emit message.new (and optionally typing) so the WebSocket
 * server can push to connected clients. When scaling to multiple instances, replace
 * with Redis Pub/Sub (Upstash REST does not support Pub/Sub; would need a TCP Redis client).
 */

export type ChatEventPayload =
  | {
      event: 'message.new'
      conversationId: string
      message: ChatMessagePayload
      recipientUserIds: string[]
    }
  | {
      event: 'message.deleted'
      conversationId: string
      messageId: string
      deletedAt: string
      recipientUserIds: string[]
    }
  | { event: 'typing'; conversationId: string; userId: string; until: string; recipientUserIds: string[] }

export type ChatMessagePayload = {
  id: string
  conversationId: string
  senderId: string
  content: string
  replyToMessageId: string | null
  createdAt: string
  updatedAt: string
  attachments?: Array<{ id: string; url: string; type: string; publicId: string }>
  sender?: { id: string; username: string | null; name: string | null; avatarUrl: string | null }
  replyTo?: { id: string; content: string; senderId: string; createdAt: string } | null
}

type Listener = (payload: ChatEventPayload) => void

const listeners: Set<Listener> = new Set()

export function subscribeChatEvents(listener: Listener): () => void {
  listeners.add(listener)
  return () => listeners.delete(listener)
}

export function publishChatEvent(payload: ChatEventPayload): void {
  const bus = typeof global !== 'undefined' && (global as unknown as { chatEventBus?: { publish: (p: ChatEventPayload) => void } }).chatEventBus
  if (bus) {
    bus.publish(payload)
    return
  }
  listeners.forEach((listener) => {
    try {
      listener(payload)
    } catch (e) {
      console.error('[ChatEvents] Listener error:', e)
    }
  })
}
