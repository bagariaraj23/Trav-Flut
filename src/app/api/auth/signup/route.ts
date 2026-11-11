import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { signupSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse } from "@/types/api";
import { withRateLimit, withLogging, withCors, handleApiError } from "@/lib/middleware";
import { sanitizeErrorForClient, handlePrismaUniqueError } from "@/lib/prismaErrors";
import { PerformanceMonitor } from "@/lib/monitoring";

export async function POST(request: NextRequest) {
  return await withCors(async (req) => {
    const loggedHandler = withLogging(async (loggedReq) => {
      return await withRateLimit(loggedReq, "auth_signup", async (rateLimitedReq) => {
        const endTimer = PerformanceMonitor.getInstance().startTimer("auth_signup");
        try {
          const body = await rateLimitedReq.json();
          // Validate input
          const validatedData = signupSchema.parse(body);
          const { email, password, name, username } = validatedData;
          // email is already normalized (trim, lowercase, invisible chars stripped) by signupSchema
          // Hash password before transaction (deterministic and fast operation)
          const hashedPassword = await AuthService.hashPassword(password);

          // Wrap check-delete-create in a single transaction to prevent race conditions
          // This ensures atomicity when handling Google-only account reclaim or deleted user email freeing
          const user = await prisma.$transaction(async (tx) => {
            // Check for existing user by email (active or soft-deleted) inside transaction
            const existingByEmail = await tx.user.findUnique({
              where: { email },
              select: {
                id: true,
                deletedAt: true,
                password: true,
                oauthAccounts: { select: { id: true } },
              },
            });

            if (existingByEmail) {
              if (existingByEmail.deletedAt == null) {
                // Active user with this email. If it's a Google-only account (no password), it was likely
                // re-created by "Sign in with Google" after the user had deleted; allow reclaim by soft-deleting it.
                const isGoogleOnly =
                  existingByEmail.password == null &&
                  existingByEmail.oauthAccounts.length > 0;

                if (isGoogleOnly) {
                  // Delete OAuth accounts and soft-delete user atomically
                  await tx.oAuthAccount.deleteMany({ where: { userId: existingByEmail.id } });
                  await tx.user.update({
                    where: { id: existingByEmail.id },
                    data: {
                      deletedAt: new Date(),
                      deleteMeta: {
                        deletedAt: new Date().toISOString(),
                        reason: "Reclaimed by email/password signup (was Google-only orphan)",
                      },
                      email: `deleted_${existingByEmail.id}_${Date.now()}@deleted.local`,
                      username: null,
                      password: null,
                      avatarUrl: null,
                      bio: null,
                    },
                  });
                  // Fall through to create the new user below
                } else {
                  // Active user with password - cannot reclaim
                  throw new Error("This email is already in use. Sign in with that account or use a different email.");
                }
              } else {
                // Soft-deleted user still has this email; free it so we can create a new account.
                await tx.user.update({
                  where: { id: existingByEmail.id },
                  data: {
                    email: `deleted_${existingByEmail.id}_${Date.now()}@deleted.local`,
                    username: null,
                  },
                });
              }
            }

            // Create new user atomically within the same transaction
            try {
              return await tx.user.create({
                data: {
                  email,
                  password: hashedPassword,
                  name,
                  username,
                },
              });
            } catch (error: any) {
              const code = error?.code as string | undefined;
              const target = error?.meta?.target;
              const targetList = Array.isArray(target)
                ? target
                : typeof target === "string"
                  ? [target]
                  : [];
              const isEmailConflict = targetList.includes("email");
              const isUsernameConflict = targetList.includes("username");

              // If username conflict, return user-friendly error
              if (code === "P2002" && isUsernameConflict) {
                throw new Error("Username already taken. Try another.");
              }

              // If email conflict (shouldn't happen in transaction, but handle gracefully)
              if (code === "P2002" && isEmailConflict) {
                throw new Error("This email is already in use. Sign in or use a different email to sign up.");
              }

              // Re-throw other errors
              throw error;
            }
          });
          // Generate tokens
          const accessToken = AuthService.generateAccessToken(user);
          const refreshToken = AuthService.generateRefreshToken(user);
          // Store refresh token
          await AuthService.storeRefreshToken(user.id, refreshToken);
          // Remove password from response
          const { password: _, ...userWithoutPassword } = user;
          const response: ApiResponse<AuthResponse> = {
            success: true,
            data: {
              user: {
                ...userWithoutPassword,
                createdAt: user.createdAt.toISOString(),
                updatedAt: user.updatedAt.toISOString(),
              },
              accessToken,
              refreshToken,
            },
          };
          return NextResponse.json(response, { status: 201 });
        } catch (error: unknown) {
          // Handle validation errors (safe to show to user)
          if (error && typeof error === "object" && "name" in error && error.name === "ZodError") {
            const zodError = error as { errors?: Array<{ message?: string }> };
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: zodError.errors?.[0]?.message || "Validation error",
              },
              { status: 400 }
            );
          }

          // Handle Error instances thrown from transaction (user-friendly messages)
          if (error instanceof Error) {
            const errorMessage = error.message;
            // Check if it's a user-friendly error message from our transaction
            if (
              errorMessage.includes("already in use") ||
              errorMessage.includes("already taken") ||
              errorMessage.includes("Sign in")
            ) {
              return NextResponse.json<ApiResponse>(
                {
                  success: false,
                  error: errorMessage,
                },
                { status: 400 }
              );
            }
          }

          // Sanitize error for client (logs technical details, returns user-friendly message)
          const { message, statusCode } = sanitizeErrorForClient(error, "signup");

          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: message,
            },
            { status: statusCode }
          );
        } finally {
          endTimer();
        }
      });
    });
    return await loggedHandler(req);
  })(request);
}
