import type { WebSocket } from "ws";
import { AuthService } from "@/lib/auth";
import {
  type ChatEventPayload,
} from "@/lib/chat-events";
import { prisma } from "@/lib/prisma";

function getChatEventBus(): { subscribe: (fn: (p: ChatEventPayload) => void) => () => void; publish: (p: ChatEventPayload) => void } | null {
  return typeof global !== "undefined" && (global as unknown as { chatEventBus?: { subscribe: (fn: (p: ChatEventPayload) => void) => () => void; publish: (p: ChatEventPayload) => void } }).chatEventBus || null;
}

type ExtendedWebSocket = WebSocket & { userId?: string };

const connectionsByUserId = new Map<string, Set<WebSocket>>();

function sendToUser(userId: string, payload: object): void {
  const conns = connectionsByUserId.get(userId);
  if (!conns) return;
  const raw = JSON.stringify(payload);
  conns.forEach((ws) => {
    if (ws.readyState === 1) {
      try {
        ws.send(raw);
      } catch (e) {
        console.error("[ChatWS] Send error:", e);
      }
    }
  });
}

export function attachChatWebSocket(
  wss: { on: (ev: "connection", cb: (ws: WebSocket, req?: unknown) => void) => void }
): void {
  const bus = getChatEventBus();
  if (!bus) {
    console.error("[ChatWS] chatEventBus not set - load lib/chat-events-bus.cjs before server. Realtime messages will not work.");
    return;
  }
  bus.subscribe((payload: ChatEventPayload) => {
    if (payload.event === "message.new") {
      payload.recipientUserIds.forEach((userId) => sendToUser(userId, payload));
    }
    if (payload.event === "message.updated") {
      payload.recipientUserIds.forEach((userId) => sendToUser(userId, payload));
    }
    if (payload.event === "message.deleted") {
      payload.recipientUserIds.forEach((userId) => sendToUser(userId, payload));
    }
    if (payload.event === "typing") {
      payload.recipientUserIds.forEach((userId) => sendToUser(userId, payload));
    }
  });

  wss.on("connection", (ws: WebSocket, req?: unknown) => {
    const extWs = ws as ExtendedWebSocket;
    const reqUrl = req && typeof req === "object" && "url" in req ? (req as { url?: string }).url : "";
    const url = reqUrl ?? "";
    const tokenMatch = url.match(/[?&]token=([^&]+)/);
    const token = tokenMatch ? decodeURIComponent(tokenMatch[1]) : null;

    const authenticate = (t: string) => {
      const payload = AuthService.verifyAccessToken(t.replace(/^Bearer\s+/i, "").trim());
      if (!payload) return false;
      extWs.userId = payload.userId;
      let set = connectionsByUserId.get(payload.userId);
      if (!set) {
        set = new Set();
        connectionsByUserId.set(payload.userId, set);
      }
      set.add(ws);
      return true;
    };

    if (token && authenticate(token)) {
      try {
        ws.send(JSON.stringify({ type: "connected", userId: extWs.userId }));
      } catch (_) {}
    }

    ws.on("message", async (data: Buffer | string) => {
      try {
        const msg = JSON.parse(data.toString());
        if (msg.type === "auth" && msg.token && !extWs.userId) {
          if (authenticate(msg.token)) {
            ws.send(JSON.stringify({ type: "connected", userId: extWs.userId }));
          } else {
            ws.send(JSON.stringify({ type: "error", message: "Invalid token" }));
          }
          return;
        }

        // Typing indicator: client sends { type: "typing", conversationId }
        if (msg.type === "typing" && typeof msg.conversationId === "string" && extWs.userId) {
          try {
            const conversationId = msg.conversationId as string;
            const senderId = extWs.userId!;

            const conv = await prisma.conversation.findUnique({
              where: { id: conversationId },
              select: {
                participants: {
                  select: { userId: true },
                },
              },
            });
            if (!conv) return;

            const participantIds = conv.participants.map((p) => p.userId);
            if (!participantIds.includes(senderId)) return;

            const recipientUserIds = participantIds.filter((id) => id !== senderId);
            if (recipientUserIds.length === 0) return;

            const until = new Date(Date.now() + 3000).toISOString();
            bus.publish({
              event: "typing",
              conversationId,
              userId: senderId,
              until,
              recipientUserIds,
            });
          } catch (e) {
            console.error("[ChatWS] Typing handling error:", e);
          }
        }
      } catch (_) {
        // ignore parse errors
      }
    });

    ws.on("close", () => {
      const uid = extWs.userId;
      if (uid) {
        const set = connectionsByUserId.get(uid);
        if (set) {
          set.delete(ws);
          if (set.size === 0) connectionsByUserId.delete(uid);
        }
      }
    });
  });
}
