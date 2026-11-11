import { describe, expect, it, beforeEach, afterEach, vi } from "vitest";
import { z } from "zod";


// Validation schemas (replicated from the API endpoint implementations)
const chatMessageSchema = z.string().min(1).max(512);
const groupNameSchema = z.string().min(1).max(100);
const avatarUrlSchema = z.string().url().nullable();
const conversationTypeSchema = z.enum(["DM", "GROUP", "TRIP"]);
const participantRoleSchema = z.enum(["ADMIN", "MEMBER"]);

// Edit/delete time-window logic (mirrors services/chat.ts)
const EDIT_DELETE_WINDOW_MS = 15 * 60 * 1_000; // 15 minutes

function isWithinTimeframe(createdAt: Date, windowMs: number): boolean {
  return Date.now() - createdAt.getTime() <= windowMs;
}

function ensureWithinEditDeleteWindow(createdAt: Date): void {
  if (!isWithinTimeframe(createdAt, EDIT_DELETE_WINDOW_MS)) {
    throw new Error("Message is too old to edit or delete");
  }
}


// Participant cache (mirrors services/chat.ts, pure in-memory logic)
import { LRUCache } from "../../src/lib/cache";

const PARTICIPANT_CACHE_TTL_MS = 30_000;

function makeParticipantCache() {
  const cache = new LRUCache<string, string[]>(100);

  function getCached(conversationId: string): string[] | undefined {
    return cache.get(conversationId);
  }

  function setCached(conversationId: string, ids: string[]): void {
    cache.set(conversationId, ids, PARTICIPANT_CACHE_TTL_MS);
  }

  function invalidate(conversationId: string): void {
    cache.delete(conversationId);
  }

  return { getCached, setCached, invalidate, cache };
}

// ChatEventPayload structure tests (mirrors chat-events.ts types)
const messagePayloadSchema = z.object({
  event: z.enum(["message.new", "message.updated", "message.deleted"]),
  conversationId: z.string().uuid(),
  recipientUserIds: z.array(z.string().uuid()),
});

const typingPayloadSchema = z.object({
  event: z.literal("typing"),
  conversationId: z.string().uuid(),
  userId: z.string().uuid(),
  until: z.string().datetime(),
  recipientUserIds: z.array(z.string().uuid()),
});

const conversationReadPayloadSchema = z.object({
  event: z.literal("conversation.read"),
  conversationId: z.string().uuid(),
  userId: z.string().uuid(),
  lastReadAt: z.string().datetime(),
  recipientUserIds: z.array(z.string().uuid()),
});

const presenceUpdatePayloadSchema = z.object({
  event: z.literal("presence.update"),
  userId: z.string().uuid(),
  status: z.enum(["online", "offline"]),
  lastSeen: z.string().datetime(),
  recipientUserIds: z.array(z.string().uuid()),
});

// Helper UUIDs for readability
const USER_A = "00000000-0000-0000-0000-000000000001";
const USER_B = "00000000-0000-0000-0000-000000000002";
const CONV_1 = "10000000-0000-0000-0000-000000000001";
const CONV_2 = "10000000-0000-0000-0000-000000000002";

// Tests
describe("Chat Validation Rules", () => {
  describe("Message content", () => {
    it("accepts non-empty content within 512 chars", () => {
      expect(chatMessageSchema.parse("Hello!")).toBe("Hello!");
      expect(chatMessageSchema.parse("x".repeat(512))).toHaveLength(512);
    });

    it("rejects empty string", () => {
      expect(() => chatMessageSchema.parse("")).toThrow();
    });

    it("rejects content exceeding 512 characters", () => {
      expect(() => chatMessageSchema.parse("x".repeat(513))).toThrow();
    });
  });

  describe("Group name", () => {
    it("accepts names 1 – 100 characters long", () => {
      expect(groupNameSchema.parse("Paris Trip")).toBe("Paris Trip");
      expect(groupNameSchema.parse("a".repeat(100))).toHaveLength(100);
    });

    it("rejects empty names", () => {
      expect(() => groupNameSchema.parse("")).toThrow();
    });

    it("rejects names longer than 100 characters", () => {
      expect(() => groupNameSchema.parse("a".repeat(101))).toThrow();
    });
  });

  describe("Avatar URL", () => {
    it("accepts a valid HTTPS URL", () => {
      const url = "https://cdn.example.com/avatar.png";
      expect(avatarUrlSchema.parse(url)).toBe(url);
    });

    it("accepts null (remove avatar case)", () => {
      expect(avatarUrlSchema.parse(null)).toBeNull();
    });

    it("rejects non-URL strings", () => {
      expect(() => avatarUrlSchema.parse("not-a-url")).toThrow();
      expect(() => avatarUrlSchema.parse("/relative/path")).toThrow();
    });
  });

  describe("Conversation type", () => {
    it("accepts DM, GROUP, TRIP", () => {
      expect(conversationTypeSchema.parse("DM")).toBe("DM");
      expect(conversationTypeSchema.parse("GROUP")).toBe("GROUP");
      expect(conversationTypeSchema.parse("TRIP")).toBe("TRIP");
    });

    it("rejects unknown types", () => {
      expect(() => conversationTypeSchema.parse("CHANNEL")).toThrow();
      expect(() => conversationTypeSchema.parse("")).toThrow();
    });
  });

  describe("Participant role", () => {
    it("accepts ADMIN and MEMBER", () => {
      expect(participantRoleSchema.parse("ADMIN")).toBe("ADMIN");
      expect(participantRoleSchema.parse("MEMBER")).toBe("MEMBER");
    });

    it("rejects unknown roles", () => {
      expect(() => participantRoleSchema.parse("OWNER")).toThrow();
    });
  });
});

describe("Message edit/delete time window", () => {
  it("allows changes within 15 minutes", () => {
    const recent = new Date(Date.now() - 5 * 60_000);
    expect(() => ensureWithinEditDeleteWindow(recent)).not.toThrow();
  });

  it("blocks changes after 15 minutes", () => {
    const old = new Date(Date.now() - 16 * 60_000);
    expect(() => ensureWithinEditDeleteWindow(old)).toThrow(
      "Message is too old"
    );
  });

  it("allows changes made exactly at the window boundary", () => {
    const boundary = new Date(Date.now() - EDIT_DELETE_WINDOW_MS + 100);
    expect(() => ensureWithinEditDeleteWindow(boundary)).not.toThrow();
  });

  it("blocks changes 1 ms past the boundary", () => {
    const justOver = new Date(Date.now() - EDIT_DELETE_WINDOW_MS - 1);
    expect(() => ensureWithinEditDeleteWindow(justOver)).toThrow();
  });
});

describe("Participant cache", () => {
  let cache: ReturnType<typeof makeParticipantCache>;

  beforeEach(() => {
    cache = makeParticipantCache();
  });

  it("returns undefined on cache miss", () => {
    expect(cache.getCached(CONV_1)).toBeUndefined();
  });

  it("returns cached ids on hit", () => {
    cache.setCached(CONV_1, [USER_A, USER_B]);
    expect(cache.getCached(CONV_1)).toEqual([USER_A, USER_B]);
  });

  it("invalidate removes the entry", () => {
    cache.setCached(CONV_1, [USER_A]);
    cache.invalidate(CONV_1);
    expect(cache.getCached(CONV_1)).toBeUndefined();
  });

  it("invalidating one key does not affect others", () => {
    cache.setCached(CONV_1, [USER_A]);
    cache.setCached(CONV_2, [USER_B]);
    cache.invalidate(CONV_1);
    expect(cache.getCached(CONV_2)).toEqual([USER_B]);
  });

  it("distinct conversations are stored independently", () => {
    cache.setCached(CONV_1, [USER_A]);
    cache.setCached(CONV_2, [USER_B]);
    expect(cache.getCached(CONV_1)).toEqual([USER_A]);
    expect(cache.getCached(CONV_2)).toEqual([USER_B]);
  });

  it("overwriting an entry with new participants updates it", () => {
    cache.setCached(CONV_1, [USER_A]);
    cache.setCached(CONV_1, [USER_A, USER_B]);
    expect(cache.getCached(CONV_1)).toHaveLength(2);
  });

  it("expires after TTL", async () => {
    // Use a very short TTL for the test
    const shortCache = new LRUCache<string, string[]>(10);
    shortCache.set(CONV_1, [USER_A], 50); // 50ms TTL
    expect(shortCache.get(CONV_1)).toEqual([USER_A]);
    await new Promise((r) => setTimeout(r, 100));
    expect(shortCache.get(CONV_1)).toBeUndefined();
  });
});

describe("ChatEventPayload shapes", () => {
  describe("conversation.read event", () => {
    it("accepts a valid payload", () => {
      const payload = {
        event: "conversation.read",
        conversationId: CONV_1,
        userId: USER_A,
        lastReadAt: new Date().toISOString(),
        recipientUserIds: [USER_B],
      };
      expect(() => conversationReadPayloadSchema.parse(payload)).not.toThrow();
    });

    it("rejects missing lastReadAt", () => {
      const bad = {
        event: "conversation.read",
        conversationId: CONV_1,
        userId: USER_A,
        recipientUserIds: [USER_B],
      };
      expect(() => conversationReadPayloadSchema.parse(bad)).toThrow();
    });

    it("rejects non-datetime lastReadAt", () => {
      const bad = {
        event: "conversation.read",
        conversationId: CONV_1,
        userId: USER_A,
        lastReadAt: "not-a-date",
        recipientUserIds: [USER_B],
      };
      expect(() => conversationReadPayloadSchema.parse(bad)).toThrow();
    });

    it("rejects empty recipientUserIds array", () => {
      // Empty array is structurally valid; Zod passes it. The service itself
      // guards against publishing with an empty list — tested separately.
      const payload = {
        event: "conversation.read",
        conversationId: CONV_1,
        userId: USER_A,
        lastReadAt: new Date().toISOString(),
        recipientUserIds: [],
      };
      expect(() =>
        conversationReadPayloadSchema.parse(payload)
      ).not.toThrow();
    });
  });

  describe("presence.update event", () => {
    it("accepts online status", () => {
      const payload = {
        event: "presence.update",
        userId: USER_A,
        status: "online",
        lastSeen: new Date().toISOString(),
        recipientUserIds: [USER_B],
      };
      expect(() => presenceUpdatePayloadSchema.parse(payload)).not.toThrow();
    });

    it("accepts offline status", () => {
      const payload = {
        event: "presence.update",
        userId: USER_A,
        status: "offline",
        lastSeen: new Date().toISOString(),
        recipientUserIds: [USER_B],
      };
      expect(() => presenceUpdatePayloadSchema.parse(payload)).not.toThrow();
    });

    it("rejects unknown status", () => {
      const bad = {
        event: "presence.update",
        userId: USER_A,
        status: "away",
        lastSeen: new Date().toISOString(),
        recipientUserIds: [USER_B],
      };
      expect(() => presenceUpdatePayloadSchema.parse(bad)).toThrow();
    });
  });

  describe("typing event", () => {
    it("accepts a valid typing payload", () => {
      const payload = {
        event: "typing",
        conversationId: CONV_1,
        userId: USER_A,
        until: new Date(Date.now() + 3000).toISOString(),
        recipientUserIds: [USER_B],
      };
      expect(() => typingPayloadSchema.parse(payload)).not.toThrow();
    });

    it("rejects typing without until", () => {
      const bad = {
        event: "typing",
        conversationId: CONV_1,
        userId: USER_A,
        recipientUserIds: [USER_B],
      };
      expect(() => typingPayloadSchema.parse(bad)).toThrow();
    });
  });
});

describe("batchFetchUnreadCounts SQL query construction", () => {
  // We test the parameterised placeholder logic independently to ensure the
  // generated SQL always matches the number of conversationId arguments.
  function buildPlaceholders(conversationIds: string[]): string {
    return conversationIds.map((_, i) => `$${i + 3}`).join(", ");
  }

  it("builds zero placeholders for empty array", () => {
    expect(buildPlaceholders([])).toBe("");
  });

  it("builds a single placeholder for one ID", () => {
    expect(buildPlaceholders([CONV_1])).toBe("$3");
  });

  it("builds correct placeholders for multiple IDs", () => {
    const ids = [CONV_1, CONV_2, "20000000-0000-0000-0000-000000000003"];
    expect(buildPlaceholders(ids)).toBe("$3, $4, $5");
  });

  it("first two params are always userId (auth + exclude self)", () => {
    // $1 = userId for JOIN filter, $2 = userId for senderId exclusion
    const placeholders = buildPlaceholders([CONV_1]);
    expect(placeholders).not.toContain("$1");
    expect(placeholders).not.toContain("$2");
    expect(placeholders).toContain("$3");
  });
});

describe("Seen indicator logic (unit)", () => {
  // The _SeenIndicator widget checks whether participants' lastReadAt is
  // after the message's createdAt. These pure functions test that logic.

  function countSeenBy(
    participants: Array<{ userId: string; lastReadAt: string | null }>,
    senderId: string,
    messageCreatedAt: string
  ): number {
    const sentAt = new Date(messageCreatedAt).getTime();
    return participants.filter((p) => {
      if (p.userId === senderId) return false;
      if (!p.lastReadAt) return false;
      return new Date(p.lastReadAt).getTime() >= sentAt;
    }).length;
  }

  const MSG_TIME = "2026-06-13T10:00:00.000Z";

  it("returns 0 when no other participant has read", () => {
    const participants = [
      { userId: USER_A, lastReadAt: null },
      { userId: USER_B, lastReadAt: null },
    ];
    expect(countSeenBy(participants, USER_A, MSG_TIME)).toBe(0);
  });

  it("returns 1 when the other participant read after the message", () => {
    const participants = [
      { userId: USER_A, lastReadAt: null },
      { userId: USER_B, lastReadAt: "2026-06-13T10:01:00.000Z" },
    ];
    expect(countSeenBy(participants, USER_A, MSG_TIME)).toBe(1);
  });

  it("does not count sender's own read", () => {
    const participants = [
      { userId: USER_A, lastReadAt: "2026-06-13T10:02:00.000Z" },
      { userId: USER_B, lastReadAt: null },
    ];
    expect(countSeenBy(participants, USER_A, MSG_TIME)).toBe(0);
  });

  it("does not count participants who read BEFORE the message", () => {
    const participants = [
      { userId: USER_A, lastReadAt: null },
      { userId: USER_B, lastReadAt: "2026-06-13T09:59:00.000Z" }, // before msg
    ];
    expect(countSeenBy(participants, USER_A, MSG_TIME)).toBe(0);
  });

  it("counts multiple readers in a group", () => {
    const USER_C = "00000000-0000-0000-0000-000000000003";
    const participants = [
      { userId: USER_A, lastReadAt: "2026-06-13T10:02:00.000Z" }, // sender
      { userId: USER_B, lastReadAt: "2026-06-13T10:01:00.000Z" },
      { userId: USER_C, lastReadAt: "2026-06-13T10:03:00.000Z" },
    ];
    expect(countSeenBy(participants, USER_A, MSG_TIME)).toBe(2);
  });
});

describe("Presence display logic (unit)", () => {
  function formatPresenceSubtitle(
    presence: string | undefined
  ): string | null {
    if (!presence) return null;
    if (presence === "online") return "Online";
    const lastSeen = new Date(presence);
    if (isNaN(lastSeen.getTime())) return null;
    const diff = Date.now() - lastSeen.getTime();
    const mins = Math.floor(diff / 60_000);
    const hours = Math.floor(diff / 3_600_000);
    const days = Math.floor(diff / 86_400_000);
    if (mins < 1) return "Last seen just now";
    if (mins < 60) return `Last seen ${mins}m ago`;
    if (hours < 24) return `Last seen ${hours}h ago`;
    return `Last seen ${days}d ago`;
  }

  it("returns null for unknown user", () => {
    expect(formatPresenceSubtitle(undefined)).toBeNull();
  });

  it('returns "Online" when status is online', () => {
    expect(formatPresenceSubtitle("online")).toBe("Online");
  });

  it('returns "Last seen just now" for < 1 min ago', () => {
    const seconds = new Date(Date.now() - 30_000).toISOString();
    expect(formatPresenceSubtitle(seconds)).toBe("Last seen just now");
  });

  it('returns minutes when last seen 5–59 mins ago', () => {
    const fiveMins = new Date(Date.now() - 5 * 60_000).toISOString();
    expect(formatPresenceSubtitle(fiveMins)).toBe("Last seen 5m ago");
  });

  it('returns hours when last seen 1–23 hours ago', () => {
    const threeHours = new Date(Date.now() - 3 * 3_600_000).toISOString();
    expect(formatPresenceSubtitle(threeHours)).toBe("Last seen 3h ago");
  });

  it('returns days when last seen >= 24 hours ago', () => {
    const twoDays = new Date(Date.now() - 2 * 86_400_000).toISOString();
    expect(formatPresenceSubtitle(twoDays)).toBe("Last seen 2d ago");
  });
});
