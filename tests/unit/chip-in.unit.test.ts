import { describe, expect, it } from "vitest";
import { parseChipInAmount, parseChipInName, publicSupporterNames } from "../../src/lib/chipIn";

describe("parseChipInAmount", () => {
  it("accepts a preset and turns it into paise", () => {
    expect(parseChipInAmount({ amountRupees: 100 })).toEqual({
      ok: true,
      rupees: 100,
      amountMinor: 10000,
    });
  });

  it("rejects fractions and amounts outside the range", () => {
    expect(parseChipInAmount({ amountRupees: 10.5 }).ok).toBe(false);
    expect(parseChipInAmount({ amountRupees: 1 }).ok).toBe(false);
    expect(parseChipInAmount({ amountRupees: 20000 }).ok).toBe(false);
    expect(parseChipInAmount({ amountRupees: "100" })).toMatchObject({ ok: true, rupees: 100 });
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
