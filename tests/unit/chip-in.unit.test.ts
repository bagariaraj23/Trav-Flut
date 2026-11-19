import { describe, expect, it } from "vitest";
import { parseChipInAmount } from "../../src/lib/chipIn";

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
