import { describe, it, expect } from "vitest";
import { bucketCoord } from "../../src/lib/cache";

describe("cache bucketCoord", () => {
  it("encodes coordinates to compact base62 buckets", () => {
    const result = bucketCoord(12.34567);
    expect(result).toBeTypeOf("string");
    // Should be stable for same input
    expect(bucketCoord(12.34567)).toEqual(result);
  });

  it("rounds to 4 decimals (approx 11m precision)", () => {
    // Values that differ only at 5th decimal AFTER rounding to 4 decimals should be same
    // 10.12340 and 10.12344 both round to 10.1234 when multiplied by 10000
    const a = bucketCoord(10.1234);
    const b = bucketCoord(10.12344); // both should round to same bucket
    expect(a).toEqual(b); // same bucket

    // But 10.12344 and 10.12345 are different because:
    // 10.12344 * 10000 = 101234.4 → rounds to 101234
    // 10.12345 * 10000 = 101234.5 → rounds to 101235
    const c = bucketCoord(10.12344);
    const d = bucketCoord(10.12345);
    expect(c).not.toEqual(d); // different buckets
  });
});
