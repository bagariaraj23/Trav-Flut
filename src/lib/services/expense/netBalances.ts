import {
  Prisma,
  TripSettlementStatus,
} from "@prisma/client";
import { prisma, PrismaTransactionClient } from "@/lib/prisma";
import { NET_COUNTING_STATUSES } from "./constants";

export type MemberNet = {
  userId: string;
  paidMinor: number;
  owedMinor: number;
  settInMinor: number;
  settOutMinor: number;
  netMinor: number;
};

type DbClient = PrismaTransactionClient | typeof prisma;

const countingStatuses = NET_COUNTING_STATUSES as unknown as TripSettlementStatus[];

export async function computeMemberNets(
  tripId: string,
  memberIds: string[],
  client: DbClient = prisma
): Promise<Map<string, MemberNet>> {
  const map = new Map<string, MemberNet>();
  for (const userId of memberIds) {
    map.set(userId, {
      userId,
      paidMinor: 0,
      owedMinor: 0,
      settInMinor: 0,
      settOutMinor: 0,
      netMinor: 0,
    });
  }

  const expenses = await client.tripExpense.findMany({
    where: { tripId, deletedAt: null },
    select: {
      payerId: true,
      amountMinor: true,
      shares: { select: { userId: true, shareMinor: true } },
    },
  });

  for (const expense of expenses) {
    const payer = map.get(expense.payerId);
    if (payer) payer.paidMinor += expense.amountMinor;
    for (const share of expense.shares) {
      const row = map.get(share.userId);
      if (row) row.owedMinor += share.shareMinor;
    }
  }

  const settlements = await client.tripSettlement.findMany({
    where: {
      tripId,
      status: { in: countingStatuses },
    },
    select: { fromUserId: true, toUserId: true, amountMinor: true },
  });

  for (const s of settlements) {
    const from = map.get(s.fromUserId);
    const to = map.get(s.toUserId);
    if (from) from.settOutMinor += s.amountMinor;
    if (to) to.settInMinor += s.amountMinor;
  }

  for (const row of Array.from(map.values())) {
    // Debtor (fromUser) paying a creditor (toUser) reduces the debt:
    // payer net rises, payee net falls. That is +settOut − settIn.
    row.netMinor =
      row.paidMinor - row.owedMinor + row.settOutMinor - row.settInMinor;
  }

  return map;
}

export function netsSumToZero(nets: Iterable<MemberNet>): boolean {
  let sum = 0;
  for (const row of Array.from(nets)) sum += row.netMinor;
  return sum === 0;
}

export function getNetMinor(
  nets: Map<string, MemberNet>,
  userId: string
): number {
  return nets.get(userId)?.netMinor ?? 0;
}

/** Prisma filter helper for live expenses. */
export const liveExpenseWhere = (tripId: string): Prisma.TripExpenseWhereInput => ({
  tripId,
  deletedAt: null,
});
