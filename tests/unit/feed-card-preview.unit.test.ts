import { describe, expect, it } from "vitest";
import {
  FEED_MAP_PIN_LIMIT,
  FEED_THREAD_PREVIEW_LIMIT,
} from "../../src/lib/feedCardPreview";

describe("feed card preview constants", () => {
  it("keeps preview caps small for feed payloads", () => {
    expect(FEED_THREAD_PREVIEW_LIMIT).toBeLessThanOrEqual(8);
    expect(FEED_MAP_PIN_LIMIT).toBeLessThanOrEqual(12);
  });
});
