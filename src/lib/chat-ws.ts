import type { WebSocket } from "ws";
import { AuthService } from "@/lib/auth";
import { type ChatEventPayload } from "@/lib/chat-events";
import { prisma } from "@/lib/prisma";
import { getCachedParticipantIds } from "@/lib/services/chat";

function getChatEventBus(): {
  subscribe: (fn: (p: ChatEventPayload) => void) => () => void;
  publish: (p: ChatEventPayload) => void;
} | null {
  return (
    (typeof global !== "undefined" &&
      (
        global as unknown as {
          chatEventBus?: {
            subscribe: (fn: (p: ChatEventPayload) => void) => () => void;
            publish: (p: ChatEventPayload) => void;
          };
        }
      ).chatEventBus) ||
    null
  );
}

// Per-connection state
type ExtendedWebSocket = WebSocket & {
  userId?: string;
  isAlive?: boolean;
  heartbeatInterval?: ReturnType<typeof setInterval>;
};

// userId → Set of open WebSocket connections (multi-tab / multi-device support)
const connectionsByUserId = new Map<string, Set<WebSocket>>();

// userId → ISO timestamp of last disconnect (for presence "last seen")
const lastSeenByUser = new Map<string, string>();

const AUTH_TIMEOUT_MS = 10_000;
const HEARTBEAT_INTERVAL_MS = 30_000;
const HEARTBEAT_GRACE_MS = 10_000; // close if no pong within this window

// Helpers
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

function closeUnauthorized(ws: WebSocket, message: string): void {
  try {
    ws.send(JSON.stringify({ type: "error", message }));
  } catch (_) {}
  try {
    ws.close(4401, "Unauthorized");
  } catch (_) {}
}

// Presence helpers
/** Returns all unique user IDs that share at least one conversation with userId. */
async function getCoParticipantIds(userId: string): Promise<string[]> {
  const rows = await prisma.conversationParticipant.findMany({
    where: {
      leftAt: null,
      conversation: {
        participants: { some: { userId, leftAt: null } },
      },
      userId: { not: userId },
    },
    select: { userId: true },
    distinct: ["userId"],
  });
  return rows.map((r) => r.userId);
}

async function broadcastPresence(
  bus: NonNullable<ReturnType<typeof getChatEventBus>>,
  userId: string,
  status: "online" | "offline",
  lastSeen?: string
): Promise<void> {
  try {
    const coParticipants = await getCoParticipantIds(userId);
    if (coParticipants.length === 0) return;
    bus.publish({
      event: "presence.update",
      userId,
      status,
      lastSeen: lastSeen ?? new Date().toISOString(),
      recipientUserIds: coParticipants,
    });
  } catch (e) {
    console.error("[ChatWS] broadcastPresence error:", e);
  }
}

// Heartbeat
function startHeartbeat(ws: ExtendedWebSocket): void {
  ws.isAlive = true;
  ws.on("pong", () => {
    ws.isAlive = true;
  });

  // After HEARTBEAT_INTERVAL_MS send a ping; if no pong arrives within
  // HEARTBEAT_GRACE_MS, terminate the connection.
  ws.heartbeatInterval = setInterval(() => {
    if (ws.isAlive === false) {
      ws.terminate();
      return;
    }
    ws.isAlive = false;
    try {
      ws.ping();
    } catch (_) {
      ws.terminate();
    }
    // Schedule the grace-period check
    setTimeout(() => {
      if (ws.isAlive === false) {
        ws.terminate();
      }
    }, HEARTBEAT_GRACE_MS);
  }, HEARTBEAT_INTERVAL_MS);
}

// Main
export function attachChatWebSocket(
  wss: {
    on: (ev: "connection", cb: (ws: WebSocket, req?: unknown) => void) => void;
  }
): void {
  const bus = getChatEventBus();
  if (!bus) {
    console.error(
      "[ChatWS] chatEventBus not set — load lib/chat-events-bus.cjs before server. Real-time messages will not work."
    );
    return;
  }

  // Event bus subscriber
  bus.subscribe((payload: ChatEventPayload) => {
    switch (payload.event) {
      case "message.new":
      case "message.updated":
      case "message.deleted":
      case "typing":
      case "conversation.read":
      case "presence.update":
        payload.recipientUserIds.forEach((uid) => sendToUser(uid, payload));
        break;
    }
  });

  // Connection handler
  wss.on("connection", (ws: WebSocket, req?: unknown) => {
    const extWs = ws as ExtendedWebSocket;
    const reqUrl =
      req && typeof req === "object" && "url" in req
        ? (req as { url?: string }).url
        : "";
    const url = reqUrl ?? "";

    // Legacy: token in URL query param is still accepted for backward compat
    // but clients should prefer the post-connect auth message (see 1a fix).
    const tokenMatch = url.match(/[?&]token=([^&]+)/);
    const token = tokenMatch ? decodeURIComponent(tokenMatch[1]) : null;

    let authTimeout: ReturnType<typeof setTimeout> | null = null;

    const clearAuthTimeout = () => {
      if (authTimeout) {
        clearTimeout(authTimeout);
        authTimeout = null;
      }
    };

    const onAuthenticated = (userId: string) => {
      clearAuthTimeout();
      startHeartbeat(extWs);
      // Broadcast online presence to co-participants.
      broadcastPresence(bus, userId, "online").catch(console.error);
    };

    const authenticate = (t: string): boolean => {
      const payload = AuthService.verifyAccessToken(
        t.replace(/^Bearer\s+/i, "").trim()
      );
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

    if (token) {
      if (!authenticate(token)) {
        closeUnauthorized(ws, "Invalid token");
        return;
      }
      try {
        ws.send(JSON.stringify({ type: "connected", userId: extWs.userId }));
      } catch (_) {}
      onAuthenticated(extWs.userId!);
    } else {
      // Client will send { type: "auth", token } as the first message.
      authTimeout = setTimeout(() => {
        if (!extWs.userId) {
          closeUnauthorized(ws, "Authentication required");
        }
      }, AUTH_TIMEOUT_MS);
    }

    // Incoming messages
    ws.on("message", async (data: Buffer | string) => {
      try {
        const msg = JSON.parse(data.toString());

        // Auth message
        if (msg.type === "auth" && msg.token && !extWs.userId) {
          if (authenticate(msg.token)) {
            ws.send(JSON.stringify({ type: "connected", userId: extWs.userId }));
            onAuthenticated(extWs.userId!);
          } else {
            closeUnauthorized(ws, "Invalid token");
          }
          return;
        }

        // Typing indicator
        if (
          msg.type === "typing" &&
          typeof msg.conversationId === "string" &&
          extWs.userId
        ) {
          try {
            const conversationId = msg.conversationId as string;
            const senderId = extWs.userId;

            // Use the cached participant list (avoids a DB round-trip per keystroke).
            const participantIds = await getCachedParticipantIds(conversationId);
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
        // ignore JSON parse errors
      }
    });

    // Disconnect
    ws.on("close", () => {
      clearAuthTimeout();
      if (extWs.heartbeatInterval) {
        clearInterval(extWs.heartbeatInterval);
        extWs.heartbeatInterval = undefined;
      }

      const uid = extWs.userId;
      if (uid) {
        const set = connectionsByUserId.get(uid);
        if (set) {
          set.delete(ws);
          if (set.size === 0) {
            connectionsByUserId.delete(uid);
            // Record last seen and broadcast offline status.
            const lastSeen = new Date().toISOString();
            lastSeenByUser.set(uid, lastSeen);
            broadcastPresence(bus, uid, "offline", lastSeen).catch(console.error);
          }
          // If user still has other open connections, they remain "online".
        }
      }
    });
  });
}

/** Exposed for the push notification service to check if a user is online. */
export function isUserConnected(userId: string): boolean {
  const set = connectionsByUserId.get(userId);
  return !!set && set.size > 0;
}
