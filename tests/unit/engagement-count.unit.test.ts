import { beforeEach, describe, expect, it, vi } from "vitest";

vi.mock("../../src/lib/prisma", () => ({
  prisma: {},
}));

vi.mock("../../src/lib/redis", () => ({
  redis: null,
  memoryCache: new Map(),
}));

import { Prisma } from "@prisma/client";
import { decrementEntityCount } from "../../src/lib/services/engagement-utils";

describe("decrementEntityCount", () => {
  const executeRaw = vi.fn();

  beforeEach(() => {
    executeRaw.mockReset();
    executeRaw.mockResolvedValue(1);
  });

  it("floors a user-post like in the update itself", async () => {
    await decrementEntityCount("USER_POST", "post-1", "likeCount", {
      $executeRaw: executeRaw,
    } as never);

    const statement = executeRaw.mock.calls[0][0] as Prisma.Sql;
    expect(statement.strings.join(" ")).toContain(
      'UPDATE "user_posts" SET "likeCount" = GREATEST(0, "likeCount" - 1)'
    );
    expect(statement.values).toEqual(["post-1"]);
  });

  it("does not write when a comment has no count of that kind", async () => {
    await decrementEntityCount("COMMENT", "comment-1", "commentCount", {
      $executeRaw: executeRaw,
    } as never);

    expect(executeRaw).not.toHaveBeenCalled();
  });
});
