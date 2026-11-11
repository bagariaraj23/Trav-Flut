import { ValidationError } from "@/lib/errors";

export type ShareRow = {
  userId: string;
  shareMinor: number;
  weight?: number | null;
};

function uniqueSortedIds(userIds: string[]): string[] {
  return Array.from(new Set(userIds)).sort((a, b) => a.localeCompare(b));
}

function assertPositiveTotal(total: number): void {
  if (!Number.isInteger(total) || total < 1) {
    throw new ValidationError("Amount must be a positive integer in minor units");
  }
}

function assertMemberIds(userIds: string[]): string[] {
  const sorted = uniqueSortedIds(userIds);
  if (sorted.length === 0) {
    throw new ValidationError("At least one person must be in the split");
  }
  return sorted;
}

function assertSharesSum(total: number, shares: ShareRow[]): ShareRow[] {
  const sum = shares.reduce((acc, s) => acc + s.shareMinor, 0);
  if (sum !== total) {
    throw new ValidationError(
      `Shares must sum to the expense amount (got ${sum}, expected ${total})`
    );
  }
  if (!shares.some((s) => s.shareMinor > 0)) {
    throw new ValidationError("At least one share must be greater than zero");
  }
  for (const s of shares) {
    if (!Number.isInteger(s.shareMinor) || s.shareMinor < 0) {
      throw new ValidationError("Each share must be a non-negative integer");
    }
  }
  return shares;
}

/** Equal split with leftover paise going to the first members in stable userId order. */
export function splitEqual(total: number, userIds: string[]): ShareRow[] {
  assertPositiveTotal(total);
  const sorted = assertMemberIds(userIds);
  const n = sorted.length;
  const base = Math.floor(total / n);
  const remainder = total % n;
  return sorted.map((userId, i) => ({
    userId,
    shareMinor: base + (i < remainder ? 1 : 0),
  }));
}

export function splitExact(
  total: number,
  shares: { userId: string; shareMinor: number }[]
): ShareRow[] {
  assertPositiveTotal(total);
  if (shares.length === 0) {
    throw new ValidationError("At least one person must be in the split");
  }
  const seen = new Set<string>();
  const rows: ShareRow[] = [];
  for (const s of shares) {
    if (seen.has(s.userId)) {
      throw new ValidationError("Duplicate user in exact split");
    }
    seen.add(s.userId);
    rows.push({ userId: s.userId, shareMinor: s.shareMinor });
  }
  return assertSharesSum(total, rows);
}

/**
 * Largest-remainder allocation so floor shares plus leftover paise equal `total`.
 * Tie-break: higher remainder, then userId ascending.
 */
export function splitByWeights(
  total: number,
  weights: { userId: string; weight: number }[]
): ShareRow[] {
  assertPositiveTotal(total);
  if (weights.length === 0) {
    throw new ValidationError("At least one person must be in the split");
  }
  const seen = new Set<string>();
  for (const w of weights) {
    if (seen.has(w.userId)) {
      throw new ValidationError("Duplicate user in weighted split");
    }
    seen.add(w.userId);
    if (!Number.isInteger(w.weight) || w.weight < 0) {
      throw new ValidationError("Weights must be non-negative integers");
    }
  }
  const W = weights.reduce((acc, w) => acc + w.weight, 0);
  if (W <= 0) {
    throw new ValidationError("Total weight must be greater than zero");
  }

  const prelim = weights.map((w) => {
    const raw = total * w.weight;
    return {
      userId: w.userId,
      weight: w.weight,
      shareMinor: Math.floor(raw / W),
      remainder: raw % W,
    };
  });

  let leftover = total - prelim.reduce((acc, p) => acc + p.shareMinor, 0);
  const ranked = [...prelim].sort((a, b) => {
    if (b.remainder !== a.remainder) return b.remainder - a.remainder;
    return a.userId.localeCompare(b.userId);
  });
  for (let i = 0; i < leftover; i++) {
    ranked[i].shareMinor += 1;
  }

  return assertSharesSum(
    total,
    prelim.map((p) => ({
      userId: p.userId,
      shareMinor: p.shareMinor,
      weight: p.weight,
    }))
  );
}

const PERCENT_BPS_TOTAL = 10_000;

export function splitPercent(
  total: number,
  percents: { userId: string; bps: number }[]
): ShareRow[] {
  const bpsSum = percents.reduce((acc, p) => acc + p.bps, 0);
  if (bpsSum !== PERCENT_BPS_TOTAL) {
    throw new ValidationError("Percentages must sum to 100%");
  }
  return splitByWeights(
    total,
    percents.map((p) => ({ userId: p.userId, weight: p.bps }))
  );
}
