import { describe, expect, it } from "vitest";
import { parseChipInAmount, parseChipInName, publicSupporterNames } from "../../src/lib/chipIn";

describe("parseChipInAmount", () => {
  it("accepts a rupee preset and turns it into paise", () => {
    expect(parseChipInAmount({ amountRupees: 100 })).toEqual({
      ok: true,
      amount: 100,
      currency: "INR",
      amountMinor: 10000,
    });
  });

  it("accepts a whole dollar amount as cents", () => {
    expect(parseChipInAmount({ amount: 10, currency: "usd" })).toEqual({
      ok: true,
      amount: 10,
      currency: "USD",
      amountMinor: 1000,
    });
  });

  it("rejects fractions, unknown currencies, and amounts outside the range", () => {
    expect(parseChipInAmount({ amountRupees: 10.5 }).ok).toBe(false);
    expect(parseChipInAmount({ amountRupees: 1 }).ok).toBe(false);
    expect(parseChipInAmount({ amountRupees: 20000 }).ok).toBe(false);
    expect(parseChipInAmount({ amount: "100" })).toMatchObject({ ok: true, amount: 100, currency: "INR" });
    expect(parseChipInAmount({ amount: 0, currency: "USD" }).ok).toBe(false);
    expect(parseChipInAmount({ amount: 501, currency: "USD" }).ok).toBe(false);
    expect(parseChipInAmount({ amount: 10, currency: "EUR" }).ok).toBe(false);
  });
});

describe("parseChipInName", () => {
  it("keeps a short name and drops an empty one", () => {
    expect(parseChipInName({ name: "  Asha   Mehta " })).toBe("Asha Mehta");
    expect(parseChipInName({ name: "   " })).toBeNull();
    expect(parseChipInName({})).toBeNull();
    expect(parseChipInName({ name: "x".repeat(50) })?.length).toBe(40);
  });
});

describe("publicSupporterNames", () => {
  it("keeps the first spelling of a repeated name", () => {
    expect(publicSupporterNames(["Asha", "Dev", "asha", null, "  ", "Meera"])).toEqual([
      "Asha",
      "Dev",
      "Meera",
    ]);
  });
});
