export type FeedCursor = {
  createdAt: Date;
  id: string;
};

export function encodeFeedCursor(createdAt: Date, id: string): string {
  return Buffer.from(
    JSON.stringify({ createdAt: createdAt.toISOString(), id }),
    "utf8"
  ).toString("base64url");
}

export function decodeFeedCursor(cursor: string): FeedCursor {
  let parsed: unknown;
  try {
    parsed = JSON.parse(Buffer.from(cursor, "base64url").toString("utf8"));
  } catch {
    throw new Error("Invalid cursor");
  }
  if (
    !parsed ||
    typeof parsed !== "object" ||
    !("createdAt" in parsed) ||
    !("id" in parsed)
  ) {
    throw new Error("Invalid cursor");
  }
  const createdAtRaw = (parsed as { createdAt: unknown }).createdAt;
  const id = (parsed as { id: unknown }).id;
  if (typeof createdAtRaw !== "string" || typeof id !== "string" || !id) {
    throw new Error("Invalid cursor");
  }
  const createdAt = new Date(createdAtRaw);
  if (Number.isNaN(createdAt.getTime())) {
    throw new Error("Invalid cursor");
  }
  return { createdAt, id };
}
