export type NetBalance = {
  userId: string;
  netMinor: number;
};

export type OpenTransfer = {
  fromUserId: string;
  toUserId: string;
  amountMinor: number;
};

/**
 * Greedy min-cash-flow: match largest creditors with largest debtors.
 * Deterministic via userId tie-break. Not NP-optimal; fine for trip-sized groups.
 */
export function simplifyDebts(balances: NetBalance[]): OpenTransfer[] {
  const creditors = balances
    .filter((b) => b.netMinor > 0)
    .map((b) => ({ ...b }))
    .sort(compareAbsThenId);
  const debtors = balances
    .filter((b) => b.netMinor < 0)
    .map((b) => ({ userId: b.userId, debt: -b.netMinor }))
    .sort((a, b) => {
      if (b.debt !== a.debt) return b.debt - a.debt;
      return a.userId.localeCompare(b.userId);
    });

  const transfers: OpenTransfer[] = [];
  let ci = 0;
  let di = 0;

  while (ci < creditors.length && di < debtors.length) {
    const c = creditors[ci];
    const d = debtors[di];
    const pay = Math.min(c.netMinor, d.debt);
    if (pay > 0) {
      transfers.push({
        fromUserId: d.userId,
        toUserId: c.userId,
        amountMinor: pay,
      });
    }
    c.netMinor -= pay;
    d.debt -= pay;
    if (c.netMinor === 0) ci += 1;
    if (d.debt === 0) di += 1;
  }

  return transfers;
}

function compareAbsThenId(a: NetBalance, b: NetBalance): number {
  if (b.netMinor !== a.netMinor) return b.netMinor - a.netMinor;
  return a.userId.localeCompare(b.userId);
}
