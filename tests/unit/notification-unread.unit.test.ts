import { beforeEach, describe, expect, it, vi } from "vitest";

const count = vi.hoisted(() => vi.fn());

vi.mock("../../src/lib/prisma", () => ({
  prisma: {
    notification: {
      count,
    },
  },
}));

vi.mock("../../src/lib/redis", () => ({
  getOrSet: async (_key: string, getter: () => Promise<unknown>) => getter(),
  invalidateCachedKey: async () => {},
}));

import { getUnreadNotificationCount } from "../../src/lib/services/notification";

describe("getUnreadNotificationCount", () => {
  beforeEach(() => {
    count.mockReset();
    count.mockResolvedValue(3);
  });

  it("counts only unread notifications whose actor still exists", async () => {
    const total = await getUnreadNotificationCount("user-1");

    expect(total).toBe(3);
    expect(count).toHaveBeenCalledWith({
      where: {
        recipientId: "user-1",
        readAt: null,
        actor: { deletedAt: null },
      },
    });
  });
});
