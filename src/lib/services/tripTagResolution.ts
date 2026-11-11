import { prisma } from "../prisma";

export type TripForTagging = {
  userId: string;
  participants: { userId: string }[];
};

export function tripMemberUserIds(trip: TripForTagging): Set<string> {
  const s = new Set<string>();
  s.add(trip.userId);
  for (const p of trip.participants) {
    s.add(p.userId);
  }
  return s;
}

/**
 * Resolves taggedUsernames from a thread entry create request to user IDs.
 * - Reserved username "all" (case-insensitive): everyone on the trip (owner + participants), except actor.
 * - Other names: users whose username matches (case-insensitive) and who are trip members (owner or participant).
 */
export async function resolveTaggedUserIdsForTripThread(params: {
  trip: TripForTagging;
  actorId: string;
  taggedUsernames: string[];
}): Promise<string[]> {
  const { trip, actorId, taggedUsernames } = params;
  if (!taggedUsernames.length) return [];

  const memberIds = tripMemberUserIds(trip);
  const lower = taggedUsernames.map((t) => t.trim().toLowerCase());
  const wantsAll = lower.some((t) => t === "all");
  const specific = taggedUsernames.filter((_, i) => lower[i] !== "all");

  const out = new Set<string>();

  if (wantsAll) {
    for (const id of Array.from(memberIds)) {
      if (id !== actorId) out.add(id);
    }
  }

  if (specific.length === 0) {
    return Array.from(out);
  }

  const members = await prisma.user.findMany({
    where: {
      id: { in: Array.from(memberIds) },
      deletedAt: null,
    },
    select: { id: true, username: true },
  });

  const wanted = new Set(specific.map((s) => s.trim().toLowerCase()));
  for (const u of members) {
    if (!u.username) continue;
    if (!wanted.has(u.username.toLowerCase())) continue;
    if (u.id === actorId) continue;
    out.add(u.id);
  }

  return Array.from(out);
}

export async function loadTripForTagging(tripId: string) {
  return prisma.trip.findUnique({
    where: { id: tripId },
    select: {
      id: true,
      userId: true,
      participants: { select: { userId: true } },
    },
  });
}

export function parseTripScopedMentions(mentionUsernames: string[]): {
  wantsAll: boolean;
  specificLower: Set<string>;
} {
  const lower = mentionUsernames.map((m) => m.trim().toLowerCase());
  const wantsAll = lower.some((m) => m === "all");
  const specificLower = new Set<string>();
  for (let i = 0; i < mentionUsernames.length; i++) {
    if (lower[i] === "all") continue;
    const t = mentionUsernames[i].trim().toLowerCase();
    if (t.length > 0) specificLower.add(t);
  }
  return { wantsAll, specificLower };
}

export async function resolveRecipientIdsForTripMentions(params: {
  trip: TripForTagging;
  actorId: string;
  wantsAll: boolean;
  specificLower: Set<string>;
}): Promise<string[]> {
  const memberIds = tripMemberUserIds(params.trip);
  const out = new Set<string>();

  if (params.wantsAll) {
    for (const id of Array.from(memberIds)) {
      if (id !== params.actorId) out.add(id);
    }
  }

  if (params.specificLower.size === 0) {
    return Array.from(out);
  }

  const members = await prisma.user.findMany({
    where: {
      id: { in: Array.from(memberIds) },
      deletedAt: null,
    },
    select: { id: true, username: true },
  });

  for (const u of members) {
    if (!u.username) continue;
    if (!params.specificLower.has(u.username.toLowerCase())) continue;
    if (u.id === params.actorId) continue;
    out.add(u.id);
  }

  return Array.from(out);
}
