import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { completeProfileSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse, UserProfile } from "@/types/api";
import { withRateLimit, withAuth, withLogging } from "@/lib/middleware";
import { handlePrismaUniqueError } from "@/lib/prismaErrors";

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
    profileComplete: true,
  };
}

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "auth_complete_profile", async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          const body = await authenticatedReq.json();
          const validatedData = completeProfileSchema.parse(body);
          const { username, password, name } = validatedData;

          const user = await prisma.user.findUnique({
            where: { id: currentUserId },
            include: { oauthAccounts: true },
          });
          if (!user) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "User not found" },
              { status: 404 }
            );
          }
          // Profile already complete (has password): still apply username/name from form, then return success
          if (user.password != null) {
            try {
              const updatedUser = await prisma.user.update({
                where: { id: currentUserId },
                data: {
                  username,
                  ...(name !== undefined && name !== "" && { name }),
                },
              });
              const { password: _p, ...userFields } = updatedUser;
              const accessToken = AuthService.generateAccessToken(updatedUser);
              const refreshToken = AuthService.generateRefreshToken(updatedUser);
              await AuthService.storeRefreshToken(updatedUser.id, refreshToken);
              const response: ApiResponse<AuthResponse> = {
                success: true,
                data: {
                  user: toUserProfile(userFields),
                  accessToken,
                  refreshToken,
                },
              };
              return NextResponse.json(response);
            } catch (error: unknown) {
              const message = handlePrismaUniqueError(error as Parameters<typeof handlePrismaUniqueError>[0], {
                username: "Username",
              });
              if (message) {
                return NextResponse.json<ApiResponse>(
                  { success: false, error: message },
                  { status: 400 }
                );
              }
              throw error;
            }
          }
          if (user.oauthAccounts.length === 0) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Complete profile is only for OAuth users" },
              { status: 400 }
            );
          }

          const hashedPassword = await AuthService.hashPassword(password);
          try {
            const updatedUser = await prisma.user.update({
              where: { id: currentUserId },
              data: {
                username,
                password: hashedPassword,
                ...(name !== undefined && name !== "" && { name }),
              },
            });
            const accessToken = AuthService.generateAccessToken(updatedUser);
            const refreshToken = AuthService.generateRefreshToken(updatedUser);
            await AuthService.storeRefreshToken(updatedUser.id, refreshToken);
            const { password: _, ...userWithoutPassword } = updatedUser;
            const response: ApiResponse<AuthResponse> = {
              success: true,
              data: {
                user: toUserProfile(userWithoutPassword),
                accessToken,
                refreshToken,
              },
            };
            return NextResponse.json(response);
          } catch (error: unknown) {
            const message = handlePrismaUniqueError(error as Parameters<typeof handlePrismaUniqueError>[0], {
              username: "Username",
            });
            if (message) {
              return NextResponse.json<ApiResponse>(
                { success: false, error: message },
                { status: 400 }
              );
            }
            throw error;
          }
        } catch (error: unknown) {
          if (error && typeof error === "object" && "name" in error && (error as { name: string }).name === "ZodError") {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: (error as { errors?: Array<{ message?: string }> }).errors?.[0]?.message || "Validation error",
              },
              { status: 400 }
            );
          }
          console.error("[API] POST /auth/complete-profile error:", error);
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Internal server error" },
            { status: 500 }
          );
        }
      });
    });
  });
  return await loggedHandler(request);
}
