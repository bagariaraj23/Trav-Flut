import { describe, expect, it } from "vitest";
import {
  createExpenseSchema,
  createSettlementSchema,
  updateExpenseSettingsSchema,
} from "../../src/lib/validation";
import { isExpenseCurrency } from "../../src/lib/services/expense/constants";

const owner = "11111111-1111-4111-8111-111111111111";
const friend = "22222222-2222-4222-8222-222222222222";

describe("createExpenseSchema", () => {
  it("accepts an equal split and trims the title", () => {
    const parsed = createExpenseSchema.parse({
      title: "  Dinner  ",
      category: "FOOD",
      amountMinor: 15000,
      payerId: owner,
      splitMethod: "EQUAL",
      memberIds: [owner, friend],
    });
    expect(parsed.title).toBe("Dinner");
    expect(parsed.memberIds).toEqual([owner, friend]);
  });

  it("rejects an empty split, a zero amount, and exact splits without shares", () => {
    expect(() =>
      createExpenseSchema.parse({
        title: "Cab",
        category: "TRANSPORT",
        amountMinor: 0,
        payerId: owner,
        splitMethod: "EQUAL",
        memberIds: [owner],
      })
    ).toThrow();

    expect(() =>
      createExpenseSchema.parse({
        title: "Cab",
        category: "TRANSPORT",
        amountMinor: 100,
        payerId: owner,
        splitMethod: "EQUAL",
        memberIds: [],
      })
    ).toThrow();

    const exact = createExpenseSchema.safeParse({
      title: "Cab",
      category: "TRANSPORT",
      amountMinor: 100,
      payerId: owner,
      splitMethod: "EXACT",
      memberIds: [owner],
    });
    expect(exact.success).toBe(false);

    const percent = createExpenseSchema.safeParse({
      title: "Cab",
      category: "TRANSPORT",
      amountMinor: 100,
      payerId: owner,
      splitMethod: "PERCENT",
      memberIds: [owner],
    });
    expect(percent.success).toBe(false);

    const shares = createExpenseSchema.safeParse({
      title: "Cab",
      category: "TRANSPORT",
      amountMinor: 100,
      payerId: owner,
      splitMethod: "SHARES",
      memberIds: [owner],
    });
    expect(shares.success).toBe(false);
  });

  it("accepts exact, percent, and weighted payloads", () => {
    expect(
      createExpenseSchema.parse({
        title: "Hotel",
        category: "STAY",
        amountMinor: 20000,
        payerId: owner,
        splitMethod: "EXACT",
        memberIds: [owner, friend],
        shares: [
          { userId: owner, shareMinor: 12000 },
          { userId: friend, shareMinor: 8000 },
        ],
      }).shares
    ).toHaveLength(2);

    expect(
      createExpenseSchema.parse({
        title: "Hotel",
        category: "STAY",
        amountMinor: 20000,
        payerId: owner,
        splitMethod: "PERCENT",
        memberIds: [owner, friend],
        percentBps: [
          { userId: owner, bps: 6000 },
          { userId: friend, bps: 4000 },
        ],
      }).percentBps?.[0].bps
    ).toBe(6000);

    expect(
      createExpenseSchema.parse({
        title: "Hotel",
        category: "STAY",
        amountMinor: 20000,
        payerId: owner,
        splitMethod: "SHARES",
        memberIds: [owner, friend],
        weights: [
          { userId: owner, weight: 2 },
          { userId: friend, weight: 1 },
        ],
      }).weights
    ).toHaveLength(2);
  });
});

describe("settlement and currency settings", () => {
  it("requires distinct-looking uuid parties and a positive amount", () => {
    expect(
      createSettlementSchema.parse({
        fromUserId: friend,
        toUserId: owner,
        amountMinor: 5000,
      }).amountMinor
    ).toBe(5000);

    expect(() =>
      createSettlementSchema.parse({
        fromUserId: friend,
        toUserId: owner,
        amountMinor: 0,
      })
    ).toThrow();
  });

  it("accepts the v1 currencies and rejects the rest", () => {
    expect(isExpenseCurrency("INR")).toBe(true);
    expect(isExpenseCurrency("JPY")).toBe(false);
    expect(
      updateExpenseSettingsSchema.parse({
        expenseCurrency: "EUR",
        spendVisibleOnDiscover: true,
      })
    ).toEqual({
      expenseCurrency: "EUR",
      spendVisibleOnDiscover: true,
    });
    expect(() =>
      updateExpenseSettingsSchema.parse({ expenseCurrency: "JPY" })
    ).toThrow();
  });
});
