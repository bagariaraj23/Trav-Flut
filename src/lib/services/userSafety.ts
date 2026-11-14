import { UserSafetyAction } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  AuthorizationError,
  NotFoundError,
  ValidationError,
} from "@/lib/errors";

const SAFETY_CACHE_TTL_MS = 15_000;

type SafetyRow = {
  actorId: string;
  targetId: string;
  action: UserSafetyAction;
};

const safetyCache = new Map<string, { at: number; rows: SafetyRow[] }>();

function invalidateSafetyCache(userId: string) {
  safetyCache.delete(userId);
}

function otherUserId(row: SafetyRow, userId: string) {
  return row.actorId === userId ? row.targetId : row.actorId;
}

async function safetyRowsInvolving(userId: string): Promise<SafetyRow[]> {
  const hit = safetyCache.get(userId);
  if (hit && Date.now() - hit.at < SAFETY_CACHE_TTL_MS) return hit.rows;
  const rows = await prisma.userSafetyRelation.findMany({
    where: { OR: [{ actorId: userId }, { targetId: userId }] },
    select: { actorId: true, targetId: true, action: true },
  });
  safetyCache.set(userId, { at: Date.now(), rows });
  return rows;
}

async function invalidateNotificationBadges(leftId: string, rightId: string) {
  const { invalidateUnreadNotificationCount } = await import("./notification");
  await Promise.all([
    invalidateUnreadNotificationCount(leftId),
    invalidateUnreadNotificationCount(rightId),
  ]);
}

export const CANNOT_MESSAGE = "You can't message this person.";
export const CANNOT_ADD =
  "You can't add this person to a trip or group you created.";
export const CANNOT_FOLLOW = "You can't follow this person.";

const userSummarySelect = {
  id: true,
  username: true,
  name: true,
  avatarUrl: true,
} as const;

export type SafetyUserSummary = {
  id: string;
  username: string | null;
  name: string | null;
  avatarUrl: string | null;
  action: UserSafetyAction;
  createdAt: string;
};

export type SafetyPair = {
  outgoing: UserSafetyAction | null;
  incoming: UserSafetyAction | null;
};

function encodeCursor(createdAt: Date, id: string): string {
  return Buffer.from(
    JSON.stringify({ createdAt: createdAt.toISOString(), id })
  ).toString("base64url");
}

function decodeCursor(cursor: string): { createdAt: Date; id: string } {
  try {
    const parsed = JSON.parse(
      Buffer.from(cursor, "base64url").toString("utf8")
    ) as { createdAt?: string; id?: string };
    if (!parsed.createdAt || !parsed.id) {
      throw new Error("missing");
    }
    const createdAt = new Date(parsed.createdAt);
    if (Number.isNaN(createdAt.getTime())) throw new Error("date");
    return { createdAt, id: parsed.id };
  } catch {
    throw new ValidationError("Invalid cursor");
  }
}

export async function blockEitherWay(
  leftId: string,
  rightId: string
): Promise<boolean> {
  if (!leftId || !rightId || leftId === rightId) return false;
  const rows = await safetyRowsInvolving(leftId);
  return rows.some(
    (row) =>
      row.action === UserSafetyAction.BLOCK &&
      ((row.actorId === leftId && row.targetId === rightId) ||
        (row.actorId === rightId && row.targetId === leftId))
  );
}

/** Direct messages stop when either person has restricted or blocked the other. */
export async function assertCanDirectMessage(
  userId: string,
  otherId: string
): Promise<void> {
  const row = await prisma.userSafetyRelation.findFirst({
    where: {
      OR: [
        { actorId: userId, targetId: otherId },
        { actorId: otherId, targetId: userId },
      ],
    },
    select: { id: true },
  });
  if (row) throw new AuthorizationError(CANNOT_MESSAGE);
}

/** The creator of a trip or group cannot add someone when a block exists either way. */
export async function assertCreatorMayAdd(
  creatorId: string,
  targetId: string
): Promise<void> {
  if (creatorId === targetId) return;
  if (await blockEitherWay(creatorId, targetId)) {
    throw new AuthorizationError(CANNOT_ADD);
  }
}

export async function isProfileUnavailable(
  profileUserId: string,
  viewerId: string | null
): Promise<boolean> {
  if (!viewerId || viewerId === profileUserId) return false;
  const row = await prisma.userSafetyRelation.findUnique({
    where: {
      actorId_targetId: { actorId: profileUserId, targetId: viewerId },
    },
    select: { action: true },
  });
  return row?.action === UserSafetyAction.BLOCK;
}

/** The signed-in person blocked this profile, so they see a limited page with Unblock. */
export async function viewerHasBlocked(
  viewerId: string | null,
  profileUserId: string
): Promise<boolean> {
  if (!viewerId || viewerId === profileUserId) return false;
  const row = await prisma.userSafetyRelation.findUnique({
    where: {
      actorId_targetId: { actorId: viewerId, targetId: profileUserId },
    },
    select: { action: true },
  });
  return row?.action === UserSafetyAction.BLOCK;
}

/** People blocked in either direction. They are absent from search and from each other's profiles. */
export async function blockedUserIds(viewerId: string): Promise<string[]> {
  const ids = new Set<string>();
  for (const row of await safetyRowsInvolving(viewerId)) {
    if (row.action === UserSafetyAction.BLOCK) ids.add(otherUserId(row, viewerId));
  }
  ids.delete(viewerId);
  return [...ids];
}

/**
 * Authors and trip owners to leave out of Home, Discover, and live trips.
 * A block in either direction hides that person.
 * A restrict hides the restrictor's posts from the restricted person's feeds.
 * Profile pages stay available under Restrict.
 */
export async function feedHiddenUserIds(viewerId: string): Promise<string[]> {
  const ids = new Set<string>();
  for (const row of await safetyRowsInvolving(viewerId)) {
    if (row.action === UserSafetyAction.BLOCK) {
      ids.add(otherUserId(row, viewerId));
    } else if (
      row.action === UserSafetyAction.RESTRICT &&
      row.targetId === viewerId
    ) {
      ids.add(row.actorId);
    }
  }
  ids.delete(viewerId);
  return [...ids];
}

/** Blocked people, either direction. Feeds that should also hide a restrictor use feedHiddenUserIds. */
export async function contentHiddenUserIds(viewerId: string): Promise<string[]> {
  return blockedUserIds(viewerId);
}

/**
 * People who must not see this person's last seen, typing, or read receipts.
 * Block hides those signals both ways. Restrict hides the restrictor's signals
 * from the person they restricted.
 */
export async function presenceHiddenRecipientIds(
  subjectId: string
): Promise<Set<string>> {
  const ids = new Set<string>();
  for (const row of await safetyRowsInvolving(subjectId)) {
    if (row.action === UserSafetyAction.BLOCK) {
      ids.add(otherUserId(row, subjectId));
    } else if (
      row.action === UserSafetyAction.RESTRICT &&
      row.actorId === subjectId
    ) {
      ids.add(row.targetId);
    }
  }
  ids.delete(subjectId);
  return ids;
}

export async function setSafetyAction(
  actorId: string,
  targetId: string,
  action: UserSafetyAction
): Promise<SafetyUserSummary> {
  if (actorId === targetId) {
    throw new ValidationError("You can't do that to yourself");
  }
  const target = await prisma.user.findUnique({
    where: { id: targetId },
    select: userSummarySelect,
  });
  if (!target) throw new NotFoundError("User not found");

  const existing = await prisma.userSafetyRelation.findUnique({
    where: { actorId_targetId: { actorId, targetId } },
  });
  if (
    action === UserSafetyAction.RESTRICT &&
    existing?.action === UserSafetyAction.BLOCK
  ) {
    throw new ValidationError(
      "Unblock this person before restricting them."
    );
  }

  const saved = await prisma.$transaction(async (tx) => {
    const row = await tx.userSafetyRelation.upsert({
      where: { actorId_targetId: { actorId, targetId } },
      create: { actorId, targetId, action },
      update: { action },
    });
    if (action === UserSafetyAction.BLOCK) {
      await tx.follow.deleteMany({
        where: {
          OR: [
            { followerId: targetId, followeeId: actorId },
            { followerId: actorId, followeeId: targetId },
          ],
        },
      });
      await tx.followRequest.deleteMany({
        where: {
          OR: [
            { followerId: targetId, followeeId: actorId },
            { followerId: actorId, followeeId: targetId },
          ],
        },
      });
    }
    return row;
  });

  invalidateSafetyCache(actorId);
  invalidateSafetyCache(targetId);
  if (action === UserSafetyAction.BLOCK) {
    await invalidateNotificationBadges(actorId, targetId);
  }

  return {
    ...target,
    action: saved.action,
    createdAt: saved.createdAt.toISOString(),
  };
}

export async function clearSafetyAction(
  actorId: string,
  targetId: string
): Promise<void> {
  const removed = await prisma.userSafetyRelation.deleteMany({
    where: { actorId, targetId },
  });
  if (removed.count === 0) throw new NotFoundError("No restriction or block");
  invalidateSafetyCache(actorId);
  invalidateSafetyCache(targetId);
  await invalidateNotificationBadges(actorId, targetId);
}

export async function getSafetyPair(
  actorId: string,
  targetId: string
): Promise<SafetyPair> {
  const [outgoing, incoming] = await Promise.all([
    prisma.userSafetyRelation.findUnique({
      where: { actorId_targetId: { actorId, targetId } },
      select: { action: true },
    }),
    prisma.userSafetyRelation.findUnique({
      where: { actorId_targetId: { actorId: targetId, targetId: actorId } },
      select: { action: true },
    }),
  ]);
  // A block is opaque to the person who was blocked. Their safety lookup
  // looks the same as a missing account. The blocker still sees their own block.
  if (
    incoming?.action === UserSafetyAction.BLOCK &&
    outgoing?.action !== UserSafetyAction.BLOCK
  ) {
    throw new NotFoundError("User not found");
  }
  return {
    outgoing: outgoing?.action ?? null,
    incoming: incoming?.action ?? null,
  };
}

export async function listSafetyActions(
  actorId: string,
  action: UserSafetyAction,
  options: { limit?: number; cursor?: string } = {}
): Promise<{
  people: SafetyUserSummary[];
  nextCursor: string | null;
  hasMore: boolean;
}> {
  const limit = Math.min(Math.max(options.limit ?? 20, 1), 50);
  const cursor = options.cursor ? decodeCursor(options.cursor) : null;
  const rows = await prisma.userSafetyRelation.findMany({
    where: {
      actorId,
      action,
      ...(cursor
        ? {
            OR: [
              { createdAt: { lt: cursor.createdAt } },
              { createdAt: cursor.createdAt, id: { lt: cursor.id } },
            ],
          }
        : {}),
    },
    orderBy: [{ createdAt: "desc" }, { id: "desc" }],
    take: limit + 1,
    include: { target: { select: userSummarySelect } },
  });
  const hasMore = rows.length > limit;
  const slice = hasMore ? rows.slice(0, limit) : rows;
  const last = slice[slice.length - 1];
  return {
    people: slice.map((row) => ({
      id: row.target.id,
      username: row.target.username,
      name: row.target.name,
      avatarUrl: row.target.avatarUrl,
      action: row.action,
      createdAt: row.createdAt.toISOString(),
    })),
    nextCursor: hasMore && last ? encodeCursor(last.createdAt, last.id) : null,
    hasMore,
  };
}
