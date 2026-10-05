import { prisma, PrismaTransactionClient } from "@/lib/prisma";
import { NET_COUNTING_STATUSES } from "./constants";
import { TripSettlementStatus } from "@prisma/client";

type DbClient = PrismaTransactionClient | typeof prisma;

const countingStatuses = NET_COUNTING_STATUSES as unknown as TripSettlementStatus[];

export type PairwiseRow = {
  otherUserId: string;
  netMinor: number;
  sharedCount: number;
  youOweMinor: number;
  theyOweMinor: number;
};

/**
 * Raw pairwise IOUs from bills (sharee owes payer), then subtract PAID/COMPLETED
 * settlements only between that pair. Positive netMinor means `viewerId` is owed.
 */
export async function computePairwise(
  tripId: string,
  viewerId: string,
  memberIds: string[],
  client: DbClient = prisma
): Promise<PairwiseRow[]> {
  const expenses = await client.tripExpense.findMany({
    where: { tripId, deletedAt: null },
    select: {
      payerId: true,
      shares: { select: { userId: true, shareMinor: true } },
    },
  });

  const pairDebt = new Map<string, number>();
  const sharedCount = new Map<string, number>();

  const key = (a: string, b: string) => `${a}->${b}`;

  const bumpDebt = (from: string, to: string, amount: number) => {
    if (from === to || amount === 0) return;
    const k = key(from, to);
    pairDebt.set(k, (pairDebt.get(k) ?? 0) + amount);
  };

  const involved = (expense: {
    payerId: string;
    shares: { userId: string }[];
  }): Set<string> => {
    const s = new Set<string>();
    s.add(expense.payerId);
    for (const sh of expense.shares) s.add(sh.userId);
    return s;
  };

  for (const expense of expenses) {
    const people = involved(expense);
    for (const share of expense.shares) {
      bumpDebt(share.userId, expense.payerId, share.shareMinor);
    }
    if (people.has(viewerId)) {
      for (const other of Array.from(people)) {
        if (other === viewerId) continue;
        sharedCount.set(other, (sharedCount.get(other) ?? 0) + 1);
      }
    }
  }

  const settlements = await client.tripSettlement.findMany({
    where: {
      tripId,
      status: { in: countingStatuses },
      OR: [{ fromUserId: viewerId }, { toUserId: viewerId }],
    },
    select: { fromUserId: true, toUserId: true, amountMinor: true },
  });

  const settlementNet = new Map<string, number>();
  for (const s of settlements) {
    const other = s.fromUserId === viewerId ? s.toUserId : s.fromUserId;
    // viewer paid other: viewer owes other less
    if (s.fromUserId === viewerId) {
      settlementNet.set(other, (settlementNet.get(other) ?? 0) + s.amountMinor);
    } else {
      settlementNet.set(other, (settlementNet.get(other) ?? 0) - s.amountMinor);
    }
  }

  const rows: PairwiseRow[] = [];
  for (const otherId of memberIds) {
    if (otherId === viewerId) continue;
    const youOweThemBills = pairDebt.get(key(viewerId, otherId)) ?? 0;
    const theyOweYouBills = pairDebt.get(key(otherId, viewerId)) ?? 0;
    let raw = theyOweYouBills - youOweThemBills;
    raw += settlementNet.get(otherId) ?? 0;
    const count = sharedCount.get(otherId) ?? 0;
    if (count === 0 && raw === 0) continue;
    rows.push({
      otherUserId: otherId,
      netMinor: raw,
      sharedCount: count,
      youOweMinor: raw < 0 ? -raw : 0,
      theyOweMinor: raw > 0 ? raw : 0,
    });
  }

  rows.sort((a, b) => Math.abs(b.netMinor) - Math.abs(a.netMinor));
  return rows;
}
