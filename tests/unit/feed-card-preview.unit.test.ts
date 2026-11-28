import { describe, expect, it } from "vitest";
import {
  FEED_MAP_PIN_LIMIT,
  FEED_THREAD_PREVIEW_LIMIT,
} from "../../src/lib/feedCardPreview";

describe("feed card preview constants", () => {
  it("keeps preview caps bounded for feed payloads", () => {
    // Soft swipeable strip — not unbounded full-thread payloads.
    expect(FEED_THREAD_PREVIEW_LIMIT).toBeGreaterThanOrEqual(10);
    expect(FEED_THREAD_PREVIEW_LIMIT).toBeLessThanOrEqual(20);
    expect(FEED_MAP_PIN_LIMIT).toBeLessThanOrEqual(12);
  });
});
