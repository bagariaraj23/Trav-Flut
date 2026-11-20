export type FeedRank = { createdAt: Date; id: string };

/** Newest first. Equal timestamps break ties by id descending, matching the SQL order. */
export function compareFeedRecency(a: FeedRank, b: FeedRank): number {
  const delta = b.createdAt.getTime() - a.createdAt.getTime();
  if (delta !== 0) return delta;
  return a.id < b.id ? 1 : a.id > b.id ? -1 : 0;
}

/**
 * How many rows each source must return before the merge.
 * A cursor page starts at the cursor, so the window is limit + 1.
 * A page number cannot skip inside each table: a post at global rank R
 * is at rank R or earlier in its own table, so each table is read from
 * the top through offset + limit + 1.
 */
export function homeFeedWindow(offset: number, limit: number): number {
  return offset + limit + 1;
}

export function sliceMergedFeed<T extends FeedRank>(
  rows: T[],
  offset: number,
  limit: number
): { items: T[]; hasNext: boolean } {
  const sorted = [...rows].sort(compareFeedRecency);
  return {
    items: sorted.slice(offset, offset + limit),
    hasNext: sorted.length > offset + limit,
  };
}
