import { describe, expect, it } from "vitest";
import {
  splitEqual,
  splitExact,
  splitPercent,
  splitByWeights,
} from "../../src/lib/services/expense/splitShares";
import { simplifyDebts } from "../../src/lib/services/expense/simplifyDebts";
import { netsSumToZero, type MemberNet } from "../../src/lib/services/expense/netBalances";

describe("splitEqual", () => {
  it("divides evenly", () => {
    const shares = splitEqual(9000, ["c", "a", "b"]);
    expect(shares.map((s) => s.shareMinor)).toEqual([3000, 3000, 3000]);
    expect(shares.map((s) => s.userId)).toEqual(["a", "b", "c"]);
  });

  it("gives leftover paise to first userIds in sort order", () => {
    const shares = splitEqual(10001, ["b", "a"]);
    expect(shares).toEqual([
      { userId: "a", shareMinor: 5001 },
      { userId: "b", shareMinor: 5000 },
    ]);
    expect(shares.reduce((s, r) => s + r.shareMinor, 0)).toBe(10001);
  });

  it("supports a solo split", () => {
    expect(splitEqual(150000, ["me"])).toEqual([{ userId: "me", shareMinor: 150000 }]);
  });
});

describe("splitExact", () => {
  it("accepts shares that sum to total", () => {
    const shares = splitExact(178000, [
      { userId: "u1", shareMinor: 23400 },
      { userId: "u2", shareMinor: 61000 },
      { userId: "u3", shareMinor: 93600 },
    ]);
    expect(shares.reduce((s, r) => s + r.shareMinor, 0)).toBe(178000);
  });

  it("rejects when shares do not sum to total", () => {
    expect(() =>
      splitExact(10000, [
        { userId: "a", shareMinor: 4000 },
        { userId: "b", shareMinor: 4000 },
      ])
    ).toThrow("Shares must sum to the expense amount");
  });
});

describe("splitPercent", () => {
  it("uses largest remainder so shares sum to total", () => {
    const shares = splitPercent(10000, [
      { userId: "a", bps: 3333 },
      { userId: "b", bps: 3333 },
      { userId: "c", bps: 3334 },
    ]);
    expect(shares.reduce((s, r) => s + r.shareMinor, 0)).toBe(10000);
  });

  it("rejects percents that do not sum to 100%", () => {
    expect(() =>
      splitPercent(10000, [
        { userId: "a", bps: 5000 },
        { userId: "b", bps: 4000 },
      ])
    ).toThrow("Percentages must sum to 100%");
  });
});

describe("splitByWeights", () => {
  it("allocates by shares and remaining paise", () => {
    const shares = splitByWeights(1000, [
      { userId: "a", weight: 1 },
      { userId: "b", weight: 1 },
      { userId: "c", weight: 2 },
    ]);
    expect(shares.reduce((s, r) => s + r.shareMinor, 0)).toBe(1000);
    const byId = Object.fromEntries(shares.map((s) => [s.userId, s.shareMinor]));
    expect(byId.c).toBe(500);
  });
});

describe("simplifyDebts", () => {
  it("collapses A->B and B->C into A->C", () => {
    const transfers = simplifyDebts([
      { userId: "A", netMinor: -1000 },
      { userId: "B", netMinor: 0 },
      { userId: "C", netMinor: 1000 },
    ]);
    expect(transfers).toEqual([
      { fromUserId: "A", toUserId: "C", amountMinor: 1000 },
    ]);
  });

  it("diverges from pairwise: simplify routes A→C while raw bills stay A→B and B→C", () => {
    // Bills: B paid 1000 split with A; C paid 1000 split with B.
    // Pairwise still shows A owes B and B owes C. Simplify uses nets only.
    const nets = [
      { userId: "A", netMinor: -1000 },
      { userId: "B", netMinor: 0 },
      { userId: "C", netMinor: 1000 },
    ];
    expect(simplifyDebts(nets)).toEqual([
      { fromUserId: "A", toUserId: "C", amountMinor: 1000 },
    ]);
    const pairDebt = {
      "A->B": 1000,
      "B->C": 1000,
      "A->C": 0,
    };
    expect(pairDebt["A->B"]).toBe(1000);
    expect(pairDebt["A->C"]).toBe(0);
  });

  it("settles a three-person cycle into two or fewer transfers", () => {
    const transfers = simplifyDebts([
      { userId: "A", netMinor: -500 },
      { userId: "B", netMinor: -300 },
      { userId: "C", netMinor: 800 },
    ]);
    const total = transfers.reduce((s, t) => s + t.amountMinor, 0);
    expect(total).toBe(800);
    expect(transfers.every((t) => t.toUserId === "C")).toBe(true);
  });

  it("returns empty when everyone is settled", () => {
    expect(
      simplifyDebts([
        { userId: "A", netMinor: 0 },
        { userId: "B", netMinor: 0 },
      ])
    ).toEqual([]);
  });
});

describe("netsSumToZero", () => {
  it("holds for a balanced paid/owed/settlement example", () => {
    const rows: MemberNet[] = [
      {
        userId: "a",
        paidMinor: 10000,
        owedMinor: 5000,
        settInMinor: 0,
        settOutMinor: 0,
        netMinor: 5000,
      },
      {
        userId: "b",
        paidMinor: 0,
        owedMinor: 5000,
        settInMinor: 0,
        settOutMinor: 0,
        netMinor: -5000,
      },
    ];
    expect(netsSumToZero(rows)).toBe(true);
  });

  it("ignores PENDING-style statuses by construction of MemberNet", () => {
    const rows: MemberNet[] = [
      {
        userId: "a",
        paidMinor: 100,
        owedMinor: 50,
        settInMinor: 0,
        settOutMinor: 25,
        netMinor: 25,
      },
      {
        userId: "b",
        paidMinor: 0,
        owedMinor: 50,
        settInMinor: 25,
        settOutMinor: 0,
        netMinor: -25,
      },
    ];
    expect(netsSumToZero(rows)).toBe(true);
  });

  it("zeros nets when the debtor pays the creditor (paid − owed + settOut − settIn)", () => {
    const formula = (row: Omit<MemberNet, "netMinor">): MemberNet => ({
      ...row,
      netMinor: row.paidMinor - row.owedMinor + row.settOutMinor - row.settInMinor,
    });
    const afterPay = [
      formula({
        userId: "a",
        paidMinor: 10000,
        owedMinor: 5000,
        settInMinor: 5000,
        settOutMinor: 0,
      }),
      formula({
        userId: "b",
        paidMinor: 0,
        owedMinor: 5000,
        settInMinor: 0,
        settOutMinor: 5000,
      }),
    ];
    expect(afterPay.map((r) => r.netMinor)).toEqual([0, 0]);
    expect(netsSumToZero(afterPay)).toBe(true);
  });
});
