import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { verifyGoogleIdToken } from "@/lib/services/googleAuth";
import { authGoogleSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse, UserProfile } from "@/types/api";
import { withRateLimit, withLogging } from "@/lib/middleware";
import { OAuthProvider } from "@prisma/client";
import { handlePrismaUniqueError, sanitizeErrorForClient } from "@/lib/prismaErrors";

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

        // 1. Lookup by email first (merge – one account per email). Exclude soft-deleted users.
        const existingByEmail = await prisma.user.findFirst({
          where: { email, deletedAt: null },
          include: { oauthAccounts: true },
        });

        if (existingByEmail) {
          // Use transaction to prevent race condition when linking OAuth account
          const user = await prisma.$transaction(async (tx) => {
            // Check again inside transaction to prevent race condition
            const hasGoogle = existingByEmail.oauthAccounts.some(
              (a) => a.provider === OAuthProvider.GOOGLE && a.providerUserId === sub
            );
            
            if (!hasGoogle) {
              try {
                await tx.oAuthAccount.create({
                  data: {
                    userId: existingByEmail.id,
                    provider: OAuthProvider.GOOGLE,
                    providerUserId: sub,
                  },
                });
              } catch (error: any) {
                // Handle unique constraint violation (P2002) - another request may have created it
                const uniqueError = handlePrismaUniqueError(error, {
                  provider_providerUserId: "OAuth account",
                });
                if (!uniqueError) {
                  // Not a unique constraint error, rethrow
                  throw error;
                }
                // OAuth account already exists (created by another concurrent request), continue
              }
            }
            
            // Fetch user with updated OAuth accounts
            return await tx.user.findUnique({
              where: { id: existingByEmail.id },
              include: { oauthAccounts: true },
            });
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
          include: { user: { select: { id: true, deletedAt: true } } },
        });

        if (oauthAccount) {
          const linkedUser = oauthAccount.user;
          // OAuth points to a deleted user → free the link and create a new account (start from zero)
          if (linkedUser.deletedAt) {
            await prisma.oAuthAccount.delete({
              where: {
                provider_providerUserId: {
                  provider: OAuthProvider.GOOGLE,
                  providerUserId: sub,
                },
              },
            });
            // Fall through to step 3 (create new user)
          } else {
            const user = await prisma.user.findUnique({
              where: { id: linkedUser.id },
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
            return NextResponse.json({
              ...response,
              requiresProfileCompletion: requiresProfileCompletion || undefined,
            });
          }
        }

        // 2b. Legacy: if a deleted user still has this email, free it and their OAuth so we can create a new account (start from zero)
        const deletedByEmail = await prisma.user.findFirst({
          where: { email, deletedAt: { not: null } },
          select: { id: true },
        });
        if (deletedByEmail) {
          await prisma.$transaction(async (tx) => {
            await tx.user.update({
              where: { id: deletedByEmail.id },
              data: {
                email: `deleted_${deletedByEmail.id}_${Date.now()}@deleted.local`,
                username: null,
              },
            });
            await tx.oAuthAccount.deleteMany({
              where: { userId: deletedByEmail.id },
            });
          });
        }

        // 3. New user: create account with Google email and send to complete-profile
        try {
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
        } catch (createError: unknown) {
          // Concurrent sign-in: another request created this user; find and return them (no duplicate account)
          const isP2002 =
            createError &&
            typeof createError === "object" &&
            "code" in createError &&
            (createError as { code: string }).code === "P2002";
          if (isP2002) {
            const existingByEmail = await prisma.user.findFirst({
              where: { email, deletedAt: null },
              include: { oauthAccounts: true },
            });
            if (existingByEmail) {
              const hasGoogle = existingByEmail.oauthAccounts.some(
                (a) => a.provider === OAuthProvider.GOOGLE && a.providerUserId === sub
              );
              if (!hasGoogle) {
                try {
                  await prisma.oAuthAccount.create({
                    data: {
                      userId: existingByEmail.id,
                      provider: OAuthProvider.GOOGLE,
                      providerUserId: sub,
                    },
                  });
                } catch {
                  // OAuth already created by concurrent request
                }
              }
              const user = await prisma.user.findUnique({
                where: { id: existingByEmail.id },
                include: { oauthAccounts: true },
              });
              if (user) {
                const accessToken = AuthService.generateAccessToken(user);
                const refreshToken = AuthService.generateRefreshToken(user);
                await AuthService.storeRefreshToken(user.id, refreshToken);
                const { password: _p, ...userWithoutPassword } = user;
                return NextResponse.json({
                  success: true,
                  data: {
                    user: {
                      ...toUserProfile(userWithoutPassword),
                      profileComplete: !!user.username,
                    },
                    accessToken,
                    refreshToken,
                  },
                  requiresProfileCompletion: !user.username || undefined,
                });
              }
            }
            const oauthAccount = await prisma.oAuthAccount.findUnique({
              where: {
                provider_providerUserId: {
                  provider: OAuthProvider.GOOGLE,
                  providerUserId: sub,
                },
              },
              include: { user: true },
            });
            if (oauthAccount && !oauthAccount.user.deletedAt) {
              const user = await prisma.user.findUnique({
                where: { id: oauthAccount.user.id },
                include: { oauthAccounts: true },
              });
              if (user) {
                const accessToken = AuthService.generateAccessToken(user);
                const refreshToken = AuthService.generateRefreshToken(user);
                await AuthService.storeRefreshToken(user.id, refreshToken);
                const { password: _p, ...userWithoutPassword } = user;
                return NextResponse.json({
                  success: true,
                  data: {
                    user: {
                      ...toUserProfile(userWithoutPassword),
                      profileComplete: !!user.username,
                    },
                    accessToken,
                    refreshToken,
                  },
                  requiresProfileCompletion: !user.username || undefined,
                });
              }
            }
          }
          throw createError;
        }
      } catch (error: unknown) {
        // Handle validation errors 
        if (error && typeof error === "object" && "name" in error && (error as { name: string }).name === "ZodError") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Validation error",
            },
            { status: 400 }
          );
        }

        // Sanitize error for client (logs technical details, returns user-friendly message)
        const { message, statusCode } = sanitizeErrorForClient(error, "google_oauth");

        return NextResponse.json<ApiResponse>(
          { success: false, error: message },
          { status: statusCode }
        );
      }
    });
  });
  return await loggedHandler(request);
}
