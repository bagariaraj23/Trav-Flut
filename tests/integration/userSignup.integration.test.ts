import { describe, it, expect, beforeEach } from "vitest";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser } from "../testUtils";

describe("User signup & uniqueness (email/username)", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("creates a user and prevents duplicate email", async () => {
    const email = "dup@example.com";
    await createUser({ email, username: "user_a" });

    await expect(
      prisma.user.create({
        data: { email, username: "user_b", password: "x" },
      })
    ).rejects.toThrow();
  });

  it("prevents duplicate username", async () => {
    const username = "myuser";
    await createUser({ email: "one@example.com", username });

    await expect(
      prisma.user.create({
        data: { email: "two@example.com", username, password: "x" },
      })
    ).rejects.toThrow();
  });
});
