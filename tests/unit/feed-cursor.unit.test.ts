import { describe, expect, it } from "vitest";
import { decodeFeedCursor, encodeFeedCursor } from "../../src/lib/feedCursor";

describe("feed cursor", () => {
  it("round-trips createdAt and id", () => {
    const createdAt = new Date("2026-04-01T12:30:00.000Z");
    const cursor = encodeFeedCursor(createdAt, "post-1");
    const decoded = decodeFeedCursor(cursor);
    expect(decoded.id).toBe("post-1");
    expect(decoded.createdAt.toISOString()).toBe(createdAt.toISOString());
  });

  it("rejects a cursor that is not the encoded payload", () => {
    expect(() => decodeFeedCursor("not-a-cursor")).toThrow(/Invalid cursor/);
  });
});
