import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { verifyGoogleIdToken } from "@/lib/services/googleAuth";
import { authGoogleSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse, UserProfile } from "@/types/api";
import { withRateLimit, withLogging } from "@/lib/middleware";
import { OAuthProvider } from "@prisma/client";

function toUserProfile(user: {
  id: string;
  email: string;
  username: string | null;
  name: string | null;
  avatarUrl: string | null;
  bio: string | null;
  isPrivate: boolean;
  createdAt: Date;
  updatedAt: Date;
}): UserProfile {
  return {
    ...user,
    username: user.username ?? undefined,
    name: user.name ?? undefined,
    avatarUrl: user.avatarUrl ?? undefined,
    bio: user.bio ?? undefined,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  };
}

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return await withRateLimit(req, "auth_google", async (rateLimitedReq) => {
      try {
        const body = await rateLimitedReq.json();
        const validatedData = authGoogleSchema.parse(body);
        const { idToken } = validatedData;

        const payload = await verifyGoogleIdToken(idToken);
        if (!payload) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Invalid Google token" },
            { status: 401 }
          );
        }

        const email = payload.email.toLowerCase().trim();
        const sub = payload.sub;
        const name = payload.name?.trim() || null;
        const picture = payload.picture?.trim() || null;

        // 1. Lookup by email first (merge – one account per email)
        const existingByEmail = await prisma.user.findUnique({
          where: { email },
          include: { oauthAccounts: true },
        });

        if (existingByEmail) {
          const hasGoogle = existingByEmail.oauthAccounts.some(
            (a) => a.provider === OAuthProvider.GOOGLE && a.providerUserId === sub
          );
          if (!hasGoogle) {
            await prisma.oAuthAccount.create({
              data: {
                userId: existingByEmail.id,
                provider: OAuthProvider.GOOGLE,
                providerUserId: sub,
              },
            });
          }
          const user = await prisma.user.findUnique({
            where: { id: existingByEmail.id },
            include: { oauthAccounts: true },
          });
          if (!user) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "User not found" },
              { status: 500 }
            );
          }
          const requiresProfileCompletion = !user.username;
          const accessToken = AuthService.generateAccessToken(user);
          const refreshToken = AuthService.generateRefreshToken(user);
          await AuthService.storeRefreshToken(user.id, refreshToken);
          const { password: _, ...userWithoutPassword } = user;
          const response: ApiResponse<AuthResponse> = {
            success: true,
            data: {
              user: {
                ...toUserProfile(userWithoutPassword),
                profileComplete: !requiresProfileCompletion,
              },
              accessToken,
              refreshToken,
            },
          };
          const res = NextResponse.json({
            ...response,
            requiresProfileCompletion: requiresProfileCompletion || undefined,
          });
          return res;
        }

        // 2. Lookup by OAuth (only if no user found by email)
        const oauthAccount = await prisma.oAuthAccount.findUnique({
          where: {
            provider_providerUserId: {
              provider: OAuthProvider.GOOGLE,
              providerUserId: sub,
            },
          },
          include: { user: true },
        });

        if (oauthAccount) {
          const user = oauthAccount.user;
          const requiresProfileCompletion = !user.username;
          const accessToken = AuthService.generateAccessToken(user);
          const refreshToken = AuthService.generateRefreshToken(user);
          await AuthService.storeRefreshToken(user.id, refreshToken);
          const { password: _, ...userWithoutPassword } = user;
          const response: ApiResponse<AuthResponse> = {
            success: true,
            data: {
              user: {
                ...toUserProfile(userWithoutPassword),
                profileComplete: !requiresProfileCompletion,
              },
              accessToken,
              refreshToken,
            },
          };
          return NextResponse.json({
            ...response,
            requiresProfileCompletion: requiresProfileCompletion || undefined,
          });
        }

        // 3. New user: create account with Google email and send to complete-profile
        const newUser = await prisma.user.create({
          data: {
            email,
            name,
            avatarUrl: picture,
            username: null,
            password: null,
            oauthAccounts: {
              create: {
                provider: OAuthProvider.GOOGLE,
                providerUserId: sub,
              },
            },
          },
          include: { oauthAccounts: true },
        });
        const accessToken = AuthService.generateAccessToken(newUser);
        const refreshToken = AuthService.generateRefreshToken(newUser);
        await AuthService.storeRefreshToken(newUser.id, refreshToken);
        const { password: __, ...userWithoutPassword } = newUser;
        const response: ApiResponse<AuthResponse> = {
          success: true,
          data: {
            user: {
              ...toUserProfile(userWithoutPassword),
              profileComplete: false,
            },
            accessToken,
            refreshToken,
          },
        };
        return NextResponse.json({
          ...response,
          requiresProfileCompletion: true,
        });
      } catch (error: unknown) {
        if (error && typeof error === "object" && "name" in error && (error as { name: string }).name === "ZodError") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Validation error",
            },
            { status: 400 }
          );
        }
        console.error("[API] POST /auth/google error:", error);
        return NextResponse.json<ApiResponse>(
          { success: false, error: "Internal server error" },
          { status: 500 }
        );
      }
    });
  });
  return await loggedHandler(request);
}
