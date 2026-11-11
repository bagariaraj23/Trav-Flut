import { UserSafetyAction } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import {
  AuthorizationError,
  NotFoundError,
  ValidationError,
} from "@/lib/errors";

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

async function blockEitherWay(
  leftId: string,
  rightId: string
): Promise<boolean> {
  const row = await prisma.userSafetyRelation.findFirst({
    where: {
      action: UserSafetyAction.BLOCK,
      OR: [
        { actorId: leftId, targetId: rightId },
        { actorId: rightId, targetId: leftId },
      ],
    },
    select: { id: true },
  });
  return row != null;
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
        where: { followerId: targetId, followeeId: actorId },
      });
      await tx.followRequest.deleteMany({
        where: { followerId: targetId, followeeId: actorId },
      });
    }
    return row;
  });

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
