import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { signupSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse } from "@/types/api";
import { withRateLimit, withLogging, withCors, handleApiError } from "@/lib/middleware";
import { sanitizeErrorForClient, handlePrismaUniqueError } from "@/lib/prismaErrors";

export async function POST(request: NextRequest) {
  return await withCors(async (req) => {
    const loggedHandler = withLogging(async (loggedReq) => {
      return await withRateLimit(loggedReq, "auth_signup", async (rateLimitedReq) => {
      try {
        const body = await rateLimitedReq.json();
        // Validate input
        const validatedData = signupSchema.parse(body);
        const { email, password, name, username } = validatedData;
        // email is already normalized (trim, lowercase, invisible chars stripped) by signupSchema
        // Check for existing user by email (active or soft-deleted) so we don't hit unique constraint
        // and so we can free the email if the only match is a deleted account or a Google-only "orphan".
        const existingByEmail = await prisma.user.findUnique({
          where: { email },
          select: {
            id: true,
            deletedAt: true,
            password: true,
            oauthAccounts: { select: { id: true } },
          },
        });
        const status = existingByEmail
          ? existingByEmail.deletedAt == null
            ? "active"
            : "deleted"
          : "none";
        const isGoogleOnly =
          existingByEmail &&
          existingByEmail.deletedAt == null &&
          existingByEmail.password == null &&
          existingByEmail.oauthAccounts.length > 0;
        console.log(
          `[signup] email="${email}" (length=${email.length}) existing=${status} googleOnly=${!!isGoogleOnly}`
        );
        if (existingByEmail) {
          if (existingByEmail.deletedAt == null) {
            // Active user with this email. If it's a Google-only account (no password), it was likely
            // re-created by "Sign in with Google" after the user had deleted; allow reclaim by soft-deleting it.
            if (isGoogleOnly) {
              await prisma.$transaction([
                prisma.oAuthAccount.deleteMany({ where: { userId: existingByEmail.id } }),
                prisma.user.update({
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
                }),
              ]);
              // Fall through to create the new user below.
            } else {
              return NextResponse.json<ApiResponse>(
                {
                  success: false,
                  error:
                    "This email is already in use. Sign in with that account or use a different email.",
                },
                { status: 400 }
              );
            }
          } else {
            // Soft-deleted user still has this email; free it so we can create a new account.
            await prisma.user.update({
              where: { id: existingByEmail.id },
              data: {
                email: `deleted_${existingByEmail.id}_${Date.now()}@deleted.local`,
                username: null,
              },
            });
          }
        }
        // Hash password
        const hashedPassword = await AuthService.hashPassword(password);
        // Try to create user; handle unique constraint (username) or race (email on deleted row)
        let user: Awaited<ReturnType<typeof prisma.user.create>> | null = null;
        for (let attempt = 0; attempt < 2; attempt++) {
          try {
            user = await prisma.user.create({
              data: {
                email,
                password: hashedPassword,
                name,
                username,
              },
            });
            break;
          } catch (error: any) {
            const code = error?.code as string | undefined;
            const target = error?.meta?.target;
            const targetList = Array.isArray(target)
              ? target
              : typeof target === "string"
                ? [target]
                : [];
            const isEmailConflict = targetList.includes("email");
            // P2002 = unique constraint. If email and first attempt, free any deleted row and retry once.
            if (code === "P2002" && isEmailConflict && attempt === 0) {
              const again = await prisma.user.findUnique({
                where: { email },
                select: { id: true, deletedAt: true },
              });
              if (again?.deletedAt != null) {
                await prisma.user.update({
                  where: { id: again.id },
                  data: {
                    email: `deleted_${again.id}_${Date.now()}@deleted.local`,
                    username: null,
                  },
                });
                continue;
              }
            }
            const message = handlePrismaUniqueError(error, {
              email: "User with this email",
              username: "Username",
            });
            if (message) {
              const isUsernameConflict = targetList.includes("username");
              const errorMessage = isEmailConflict
                ? "This email is already in use. Sign in or use a different email to sign up."
                : isUsernameConflict
                  ? "Username already taken. Try another."
                  : message;
              return NextResponse.json<ApiResponse>(
                { success: false, error: errorMessage },
                { status: 400 }
              );
            }
            throw error;
          }
        }
        if (!user) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Failed to create account. Please try again." },
            { status: 500 }
          );
        }
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

        // Sanitize error for client (logs technical details, returns user-friendly message)
        const { message, statusCode } = sanitizeErrorForClient(error, "signup");

        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: message,
          },
          { status: statusCode }
        );
      }
      });
    });
    return await loggedHandler(req);
  })(request);
}
