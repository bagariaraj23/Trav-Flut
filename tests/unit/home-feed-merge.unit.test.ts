import { describe, expect, it } from "vitest";
import { homeFeedWindow, sliceMergedFeed } from "../../src/lib/homeFeedMerge";

function row(id: string, time: number) {
  return { id, createdAt: new Date(time), source: id[0] };
}

describe("sliceMergedFeed", () => {
  const trips = [row("t1", 50), row("t2", 40), row("t3", 10)];
  const directs = [row("d1", 45), row("d2", 30)];
  const merged = [...trips, ...directs];

  it("keeps the merged order on the first page", () => {
    expect(homeFeedWindow(0, 2)).toBe(3);
    const page = sliceMergedFeed(merged, 0, 2);
    expect(page.items.map((item) => item.id)).toEqual(["t1", "d1"]);
    expect(page.hasNext).toBe(true);
  });

  it("does not drop a trip post that sits between direct posts on the next page", () => {
    const page = sliceMergedFeed(merged, 2, 2);
    expect(page.items.map((item) => item.id)).toEqual(["t2", "d2"]);
    expect(page.hasNext).toBe(true);
    expect(sliceMergedFeed(merged, 4, 2).items.map((item) => item.id)).toEqual(["t3"]);
  });
});
