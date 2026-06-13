import { beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { prisma } from "../../src/lib/prisma";
import { AuthService } from "../../src/lib/auth";
import { cleanDb, createUser, getAuthToken } from "../testUtils";
import { POST as loginRoute } from "../../src/app/api/auth/login/route";
import { POST as refreshRoute } from "../../src/app/api/auth/refresh-token/route";
import { POST as logoutRoute } from "../../src/app/api/auth/logout/route";
import { POST as completeProfileRoute } from "../../src/app/api/auth/complete-profile/route";

function request(
  url: string,
  body: unknown,
  token?: string,
  method: string = "POST"
): NextRequest {
  const headers = new Headers();
  headers.set("Content-Type", "application/json");
  if (token) headers.set("authorization", `Bearer ${token}`);
  return new NextRequest(url, {
    method,
    headers,
    body: JSON.stringify(body),
  });
}

async function json(response: Response) {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

describe("Auth route flow", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("logs in with username, rotates refresh token, and logs out current device", async () => {
    const user = await createUser({
      email: "auth-flow@test.com",
      username: "auth_flow",
      password: "Password123!",
    });

    const loginResponse = await loginRoute(
      request("http://localhost/api/auth/login", {
        email: "AUTH_FLOW",
        password: "Password123!",
      })
    );
    const loginData = await json(loginResponse);

    expect(loginResponse.status).toBe(200);
    expect(loginData.success).toBe(true);
    expect(loginData.data.user.id).toBe(user.id);
    expect(loginData.data.accessToken).toEqual(expect.any(String));
    expect(loginData.data.refreshToken).toEqual(expect.any(String));
    await expect(
      prisma.jWTRefreshToken.findUnique({
        where: { refreshToken: loginData.data.refreshToken },
      })
    ).resolves.toBeTruthy();

    const refreshResponse = await refreshRoute(
      request("http://localhost/api/auth/refresh-token", {
        refreshToken: loginData.data.refreshToken,
      })
    );
    const refreshData = await json(refreshResponse);

    expect(refreshResponse.status).toBe(200);
    expect(refreshData.success).toBe(true);
    expect(refreshData.data.refreshToken).not.toBe(loginData.data.refreshToken);
    await expect(
      prisma.jWTRefreshToken.findUnique({
        where: { refreshToken: loginData.data.refreshToken },
      })
    ).resolves.toBeNull();
    await expect(
      prisma.jWTRefreshToken.findUnique({
        where: { refreshToken: refreshData.data.refreshToken },
      })
    ).resolves.toBeTruthy();

    const logoutResponse = await logoutRoute(
      request(
        "http://localhost/api/auth/logout",
        { refreshToken: refreshData.data.refreshToken },
        refreshData.data.accessToken
      )
    );

    expect(logoutResponse.status).toBe(200);
    expect((await json(logoutResponse)).success).toBe(true);
    await expect(
      prisma.jWTRefreshToken.findUnique({
        where: { refreshToken: refreshData.data.refreshToken },
      })
    ).resolves.toBeNull();
  });

  it("rejects invalid credentials and missing refresh token", async () => {
    await createUser({
      email: "bad-login@test.com",
      username: "bad_login",
      password: "Password123!",
    });

    const loginResponse = await loginRoute(
      request("http://localhost/api/auth/login", {
        email: "bad-login@test.com",
        password: "WrongPassword123!",
      })
    );
    const refreshResponse = await refreshRoute(
      request("http://localhost/api/auth/refresh-token", {})
    );

    expect(loginResponse.status).toBe(401);
    expect((await json(loginResponse)).error).toBe("Invalid email or password");
    expect(refreshResponse.status).toBe(400);
    expect((await json(refreshResponse)).error).toBe("Refresh token is required");
  });

  it("completes an OAuth-created profile and rejects non-OAuth incomplete users", async () => {
    const oauthUser = await prisma.user.create({
      data: {
        email: "oauth-profile@test.com",
        name: "OAuth User",
      },
    });
    await prisma.oAuthAccount.create({
      data: {
        userId: oauthUser.id,
        provider: "GOOGLE",
        providerUserId: "google-oauth-profile",
      },
    });
    const oauthToken = await getAuthToken(oauthUser);

    const completeResponse = await completeProfileRoute(
      request(
        "http://localhost/api/auth/complete-profile",
        {
          username: "OAuth_User",
          password: "Password123!",
          name: "OAuth User",
        },
        oauthToken
      )
    );
    const completeData = await json(completeResponse);

    expect(completeResponse.status).toBe(200);
    expect(completeData.success).toBe(true);
    expect(completeData.data.user.username).toBe("oauth_user");
    const updatedOauthUser = await prisma.user.findUniqueOrThrow({
      where: { id: oauthUser.id },
    });
    expect(updatedOauthUser.password).toEqual(expect.any(String));
    await expect(
      AuthService.comparePassword("Password123!", updatedOauthUser.password!)
    ).resolves.toBe(true);

    const incompleteUser = await prisma.user.create({
      data: { email: "non-oauth-incomplete@test.com" },
    });
    const incompleteToken = await getAuthToken(incompleteUser);

    const rejectedResponse = await completeProfileRoute(
      request(
        "http://localhost/api/auth/complete-profile",
        {
          username: "plain_user",
          password: "Password123!",
        },
        incompleteToken
      )
    );

    expect(rejectedResponse.status).toBe(400);
    expect((await json(rejectedResponse)).error).toBe(
      "Complete profile is only for OAuth users"
    );
  });
});
