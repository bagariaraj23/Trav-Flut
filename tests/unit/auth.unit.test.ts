import { describe, expect, it, vi } from "vitest";

vi.mock("../../src/lib/prisma", () => ({
  prisma: {},
}));

import { AuthService } from "../../src/lib/auth";

describe("AuthService", () => {
  const user = {
    id: "user-123",
    email: "user@example.com",
  } as any;

  it("generates and verifies access tokens with user identity", () => {
    const token = AuthService.generateAccessToken(user);
    const payload = AuthService.verifyAccessToken(token);

    expect(payload).toMatchObject({
      userId: user.id,
      email: user.email,
    });
    expect(payload?.iat).toEqual(expect.any(Number));
    expect(payload?.exp).toEqual(expect.any(Number));
  });

  it("generates and verifies refresh tokens separately from access tokens", () => {
    const token = AuthService.generateRefreshToken(user);
    const payload = AuthService.verifyRefreshToken(token);

    expect(payload).toMatchObject({
      userId: user.id,
      email: user.email,
    });
    expect(payload?.iat).toEqual(expect.any(Number));
    expect(payload?.exp).toEqual(expect.any(Number));
  });

  it("returns null for malformed tokens instead of throwing", () => {
    expect(AuthService.verifyAccessToken("not-a-jwt")).toBeNull();
    expect(AuthService.verifyRefreshToken("not-a-jwt")).toBeNull();
  });

  it("hashes and compares passwords", async () => {
    const hash = await AuthService.hashPassword("Password123!");

    expect(hash).not.toBe("Password123!");
    await expect(AuthService.comparePassword("Password123!", hash)).resolves.toBe(
      true
    );
    await expect(AuthService.comparePassword("wrong-password", hash)).resolves.toBe(
      false
    );
  });
});
