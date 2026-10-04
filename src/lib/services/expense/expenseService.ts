import {
  ExpenseCategory,
  ExpenseSplitMethod,
  Prisma,
  TripSettlementStatus,
} from "@prisma/client";
import { prisma, PrismaTransactionClient } from "@/lib/prisma";
import {
  AuthorizationError,
  NotFoundError,
  ValidationError,
  ConflictError,
} from "@/lib/errors";
import { tripMemberUserIds, type TripForTagging } from "@/lib/services/tripTagResolution";
import {
  DEFAULT_EXPENSE_CURRENCY,
  isExpenseCurrency,
  MAX_AMOUNT_MINOR,
  MIN_AMOUNT_MINOR,
} from "./constants";
import {
  splitEqual,
  splitExact,
  splitPercent,
  splitByWeights,
  type ShareRow,
} from "./splitShares";
import { computeMemberNets, netsSumToZero } from "./netBalances";
import { simplifyDebts } from "./simplifyDebts";
import { computePairwise } from "./pairwise";
import { assertZeroNet } from "./assertZeroNet";

type DbClient = PrismaTransactionClient | typeof prisma;

const USER_PUBLIC_SELECT = {
  id: true,
  email: true,
  username: true,
  name: true,
  avatarUrl: true,
  bio: true,
  isPrivate: true,
  createdAt: true,
  updatedAt: true,
} as const;

export type CreateExpenseInput = {
  title: string;
  category: ExpenseCategory;
  amountMinor: number;
  payerId: string;
  splitMethod: ExpenseSplitMethod;
  memberIds: string[];
  shares?: { userId: string; shareMinor: number }[];
  percentBps?: { userId: string; bps: number }[];
  weights?: { userId: string; weight: number }[];
  note?: string | null;
};

function loadTripForMembers(tripId: string, client: DbClient = prisma) {
  return client.trip.findUnique({
    where: { id: tripId },
    select: {
      id: true,
      userId: true,
      expenseCurrency: true,
      totalSpendMinor: true,
      participants: { select: { userId: true } },
    },
  });
}

export function assertTripMember(
  trip: TripForTagging,
  userId: string
): Set<string> {
  const members = tripMemberUserIds(trip);
  if (!members.has(userId)) {
    throw new AuthorizationError(
      "Access denied. You must be the trip owner or a participant."
    );
  }
  return members;
}

function computeShares(input: CreateExpenseInput): ShareRow[] {
  const { amountMinor, splitMethod, memberIds } = input;
  if (amountMinor < MIN_AMOUNT_MINOR || amountMinor > MAX_AMOUNT_MINOR) {
    throw new ValidationError("Amount is out of range");
  }
  switch (splitMethod) {
    case "EQUAL":
      return splitEqual(amountMinor, memberIds);
    case "EXACT":
      if (!input.shares?.length) {
        throw new ValidationError("Exact split requires share amounts");
      }
      return splitExact(amountMinor, input.shares);
    case "PERCENT":
      if (!input.percentBps?.length) {
        throw new ValidationError("Percent split requires percentages");
      }
      return splitPercent(amountMinor, input.percentBps);
    case "SHARES":
      if (!input.weights?.length) {
        throw new ValidationError("Shares split requires weights");
      }
      return splitByWeights(amountMinor, input.weights);
    default:
      throw new ValidationError("Invalid split method");
  }
}

function assertIdsInMembers(ids: string[], members: Set<string>, label: string) {
  for (const id of ids) {
    if (!members.has(id)) {
      throw new ValidationError(`${label} must be a current trip member`);
    }
  }
}

export async function createExpense(params: {
  tripId: string;
  actorId: string;
  input: CreateExpenseInput;
}) {
  const { tripId, actorId, input } = params;
  const trip = await loadTripForMembers(tripId);
  if (!trip) throw new NotFoundError("Trip not found");
  const members = assertTripMember(trip, actorId);

  assertIdsInMembers([input.payerId], members, "Payer");
  assertIdsInMembers(input.memberIds, members, "Split member");
  if (input.shares) {
    assertIdsInMembers(input.shares.map((s) => s.userId), members, "Share user");
  }
  if (input.percentBps) {
    assertIdsInMembers(input.percentBps.map((s) => s.userId), members, "Share user");
  }
  if (input.weights) {
    assertIdsInMembers(input.weights.map((s) => s.userId), members, "Share user");
  }

  const shareRows = computeShares(input);

  const created = await prisma.$transaction(async (tx) => {
    const expense = await tx.tripExpense.create({
      data: {
        tripId,
        createdById: actorId,
        payerId: input.payerId,
        title: input.title,
        category: input.category,
        amountMinor: input.amountMinor,
        currency: trip.expenseCurrency || DEFAULT_EXPENSE_CURRENCY,
        splitMethod: input.splitMethod,
        note: input.note ?? null,
        shares: {
          create: shareRows.map((s) => ({
            userId: s.userId,
            shareMinor: s.shareMinor,
            weight: s.weight ?? null,
          })),
        },
      },
      include: expenseInclude,
    });

    await tx.trip.update({
      where: { id: tripId },
      data: { totalSpendMinor: { increment: input.amountMinor } },
    });

    return expense;
  });

  return serializeExpense(created);
}

const expenseInclude = {
  createdBy: { select: USER_PUBLIC_SELECT },
  payer: { select: USER_PUBLIC_SELECT },
  shares: {
    include: { user: { select: USER_PUBLIC_SELECT } },
  },
} as const;

type ExpenseRow = Prisma.TripExpenseGetPayload<{ include: typeof expenseInclude }>;

function serializeUser(u: {
  id: string;
  email: string;
  username: string | null;
  name: string | null;
  avatarUrl: string | null;
  bio: string | null;
  isPrivate: boolean;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    ...u,
    createdAt: u.createdAt.toISOString(),
    updatedAt: u.updatedAt.toISOString(),
  };
}

export function serializeExpense(expense: ExpenseRow) {
  return {
    id: expense.id,
    tripId: expense.tripId,
    createdById: expense.createdById,
    payerId: expense.payerId,
    title: expense.title,
    category: expense.category,
    amountMinor: expense.amountMinor,
    currency: expense.currency,
    splitMethod: expense.splitMethod,
    note: expense.note,
    createdAt: expense.createdAt.toISOString(),
    createdBy: serializeUser(expense.createdBy),
    payer: serializeUser(expense.payer),
    shares: expense.shares.map((s) => ({
      userId: s.userId,
      shareMinor: s.shareMinor,
      weight: s.weight,
      user: serializeUser(s.user),
    })),
  };
}

export async function listExpenses(params: {
  tripId: string;
  actorId: string;
  page: number;
  limit: number;
}) {
  const { tripId, actorId, page, limit } = params;
  const trip = await loadTripForMembers(tripId);
  if (!trip) throw new NotFoundError("Trip not found");
  assertTripMember(trip, actorId);

  const where = { tripId, deletedAt: null };
  const [total, items] = await Promise.all([
    prisma.tripExpense.count({ where }),
    prisma.tripExpense.findMany({
      where,
      include: expenseInclude,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      skip: (page - 1) * limit,
      take: limit,
    }),
  ]);

  return {
    items: items.map(serializeExpense),
    page,
    limit,
    total,
    hasNext: page * limit < total,
  };
}

export async function deleteExpense(params: {
  tripId: string;
  expenseId: string;
  actorId: string;
}) {
  const { tripId, expenseId, actorId } = params;
  const trip = await loadTripForMembers(tripId);
  if (!trip) throw new NotFoundError("Trip not found");
  assertTripMember(trip, actorId);

  const expense = await prisma.tripExpense.findFirst({
    where: { id: expenseId, tripId, deletedAt: null },
  });
  if (!expense) throw new NotFoundError("Expense not found");

  const isOwner = trip.userId === actorId;
  if (expense.createdById !== actorId && !isOwner) {
    throw new AuthorizationError("Only the creator or trip owner can delete this expense");
  }

    await prisma.$transaction(async (tx) => {
      await tx.tripExpense.update({
        where: { id: expenseId },
        data: { deletedAt: new Date() },
      });
      await tx.trip.update({
        where: { id: tripId },
        data: { totalSpendMinor: { decrement: expense.amountMinor } },
      });
    });

    return { id: expenseId, deleted: true };
  }

export async function getExpenseSummary(params: {
  tripId: string;
  actorId: string;
}) {
  const { tripId, actorId } = params;
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: {
      id: true,
      userId: true,
      expenseCurrency: true,
      totalSpendMinor: true,
      participants: { select: { userId: true } },
    },
  });
  if (!trip) throw new NotFoundError("Trip not found");
  const memberIds = Array.from(assertTripMember(trip, actorId));

  const users = await prisma.user.findMany({
    where: { id: { in: memberIds } },
    select: USER_PUBLIC_SELECT,
  });
  const userMap = new Map(users.map((u) => [u.id, u]));

  const nets = await computeMemberNets(tripId, memberIds);
  if (!netsSumToZero(nets.values())) {
    console.error("[expense] net sum invariant failed", tripId);
  }

  const openTransfers = simplifyDebts(
    Array.from(nets.values()).map((n) => ({
      userId: n.userId,
      netMinor: n.netMinor,
    }))
  ).map((t) => ({
    ...t,
    canMarkPaid: t.toUserId === actorId,
  }));

  const recorded = await prisma.tripSettlement.findMany({
    where: { tripId, status: TripSettlementStatus.PAID },
    orderBy: { createdAt: "desc" },
    include: {
      fromUser: { select: USER_PUBLIC_SELECT },
      toUser: { select: USER_PUBLIC_SELECT },
    },
  });

  const pairwise = await computePairwise(tripId, actorId, memberIds);

  return {
    currency: trip.expenseCurrency || DEFAULT_EXPENSE_CURRENCY,
    totalSpendMinor: trip.totalSpendMinor,
    myNetMinor: nets.get(actorId)?.netMinor ?? 0,
    members: memberIds.map((id) => {
      const u = userMap.get(id);
      const n = nets.get(id);
      return {
        userId: id,
        name: u?.name ?? null,
        username: u?.username ?? null,
        avatarUrl: u?.avatarUrl ?? null,
        netMinor: n?.netMinor ?? 0,
        paidMinor: n?.paidMinor ?? 0,
        owedMinor: n?.owedMinor ?? 0,
      };
    }),
    openTransfers,
    recordedSettlements: recorded.map((s) => ({
      id: s.id,
      fromUserId: s.fromUserId,
      toUserId: s.toUserId,
      amountMinor: s.amountMinor,
      status: s.status,
      createdAt: s.createdAt.toISOString(),
      fromUser: serializeUser(s.fromUser),
      toUser: serializeUser(s.toUser),
      canUndo: s.toUserId === actorId || trip.userId === actorId,
    })),
    pairwise,
  };
}

export async function recordSettlement(params: {
  tripId: string;
  actorId: string;
  fromUserId: string;
  toUserId: string;
  amountMinor: number;
}) {
  const { tripId, actorId, fromUserId, toUserId, amountMinor } = params;
  if (fromUserId === toUserId) {
    throw new ValidationError("Payer and payee must be different people");
  }
  if (actorId !== toUserId) {
    throw new AuthorizationError("Only the payee can mark a transfer as paid");
  }

  const trip = await loadTripForMembers(tripId);
  if (!trip) throw new NotFoundError("Trip not found");
  const members = assertTripMember(trip, actorId);
  assertIdsInMembers([fromUserId, toUserId], members, "Settlement party");

  if (amountMinor < MIN_AMOUNT_MINOR || amountMinor > MAX_AMOUNT_MINOR) {
    throw new ValidationError("Amount is out of range");
  }

  const created = await prisma.$transaction(async (tx) => {
    await lockTripRow(tx, tripId);
    const nets = await computeMemberNets(tripId, Array.from(members), tx);
    const fromNet = nets.get(fromUserId)?.netMinor ?? 0;
    const toNet = nets.get(toUserId)?.netMinor ?? 0;
    const maxPayable = Math.min(-fromNet, toNet);
    if (maxPayable <= 0 || amountMinor > maxPayable) {
      throw new ConflictError("This transfer is no longer valid; refresh settle-up");
    }

    const open = simplifyDebts(
      Array.from(nets.values()).map((n) => ({
        userId: n.userId,
        netMinor: n.netMinor,
      }))
    );
    const matchesSuggestion = open.some(
      (t) =>
        t.fromUserId === fromUserId &&
        t.toUserId === toUserId &&
        t.amountMinor === amountMinor
    );
    if (!matchesSuggestion) {
      throw new ConflictError("This transfer is no longer valid; refresh settle-up");
    }

    return tx.tripSettlement.create({
      data: {
        tripId,
        fromUserId,
        toUserId,
        amountMinor,
        currency: trip.expenseCurrency || DEFAULT_EXPENSE_CURRENCY,
        status: TripSettlementStatus.PAID,
        recordedById: actorId,
      },
      include: {
        fromUser: { select: USER_PUBLIC_SELECT },
        toUser: { select: USER_PUBLIC_SELECT },
      },
    });
  });

  return {
    id: created.id,
    fromUserId: created.fromUserId,
    toUserId: created.toUserId,
    amountMinor: created.amountMinor,
    status: created.status,
    createdAt: created.createdAt.toISOString(),
    fromUser: serializeUser(created.fromUser),
    toUser: serializeUser(created.toUser),
  };
}

export async function undoSettlement(params: {
  tripId: string;
  settlementId: string;
  actorId: string;
}) {
  const { tripId, settlementId, actorId } = params;
  const trip = await loadTripForMembers(tripId);
  if (!trip) throw new NotFoundError("Trip not found");
  assertTripMember(trip, actorId);

  const isOwner = trip.userId === actorId;

  await prisma.$transaction(async (tx) => {
    await lockTripRow(tx, tripId);
    const settlement = await tx.tripSettlement.findFirst({
      where: { id: settlementId, tripId },
    });
    if (!settlement) throw new NotFoundError("Settlement not found");
    if (settlement.toUserId !== actorId && !isOwner) {
      throw new AuthorizationError("Only the payee or trip owner can undo this");
    }
    await tx.tripSettlement.delete({ where: { id: settlementId } });
  });
  return { id: settlementId, deleted: true };
}

async function lockTripRow(tx: PrismaTransactionClient, tripId: string) {
  const locked = await tx.$queryRaw<Array<{ id: string }>>`
    SELECT id FROM trips WHERE id = ${tripId} FOR UPDATE
  `;
  if (locked.length === 0) throw new NotFoundError("Trip not found");
}

export async function updateExpenseSettings(params: {
  tripId: string;
  actorId: string;
  expenseCurrency?: string;
  spendVisibleOnDiscover?: boolean;
}) {
  const trip = await prisma.trip.findUnique({
    where: { id: params.tripId },
    select: {
      userId: true,
      expenseCurrency: true,
      spendVisibleOnDiscover: true,
      _count: { select: { expenses: { where: { deletedAt: null } } } },
    },
  });
  if (!trip) throw new NotFoundError("Trip not found");
  if (trip.userId !== params.actorId) {
    throw new AuthorizationError("Only the trip owner can change expense settings");
  }

  const data: Prisma.TripUpdateInput = {};
  if (params.expenseCurrency !== undefined) {
    if (!isExpenseCurrency(params.expenseCurrency)) {
      throw new ValidationError("Unsupported currency");
    }
    if (trip._count.expenses > 0 && params.expenseCurrency !== trip.expenseCurrency) {
      throw new ConflictError("Currency is locked after the first expense");
    }
    data.expenseCurrency = params.expenseCurrency;
  }
  if (params.spendVisibleOnDiscover !== undefined) {
    data.spendVisibleOnDiscover = params.spendVisibleOnDiscover;
  }

  const updated = await prisma.trip.update({
    where: { id: params.tripId },
    data,
    select: {
      expenseCurrency: true,
      spendVisibleOnDiscover: true,
      totalSpendMinor: true,
    },
  });
  return updated;
}

export async function assertMemberZeroNetOnTrip(
  tripId: string,
  userId: string
): Promise<void> {
  const trip = await loadTripForMembers(tripId);
  if (!trip) throw new NotFoundError("Trip not found");
  const memberIds = Array.from(tripMemberUserIds(trip));
  await assertZeroNet(tripId, userId, memberIds);
}

export async function assertUserHasNoUnsettledTrips(userId: string): Promise<void> {
  const owned = await prisma.trip.findMany({
    where: { userId },
    select: { id: true, userId: true, participants: { select: { userId: true } } },
  });
  const participating = await prisma.tripParticipant.findMany({
    where: { userId },
    select: {
      trip: {
        select: { id: true, userId: true, participants: { select: { userId: true } } },
      },
    },
  });

  const trips = new Map<string, TripForTagging & { id: string }>();
  for (const t of owned) trips.set(t.id, t);
  for (const p of participating) trips.set(p.trip.id, p.trip);

  for (const trip of trips.values()) {
    const memberIds = Array.from(tripMemberUserIds(trip));
    await assertZeroNet(trip.id, userId, memberIds);
  }
}
