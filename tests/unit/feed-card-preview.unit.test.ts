import { describe, expect, it } from "vitest";
import { FEED_MAP_PIN_LIMIT } from "../../src/lib/feedCardPreview";

describe("feed card preview constants", () => {
  it("keeps map pin caps small for feed payloads", () => {
    expect(FEED_MAP_PIN_LIMIT).toBeLessThanOrEqual(12);
  });
});
