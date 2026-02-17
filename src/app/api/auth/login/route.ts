import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { loginSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse } from "@/types/api";
import { withRateLimit, withLogging, withCors, handleApiError } from "@/lib/middleware";
import { sanitizeErrorForClient } from "@/lib/prismaErrors";

export async function POST(request: NextRequest) {
  return await withCors(async (req) => {
    const loggedHandler = withLogging(async (loggedReq) => {
      return await withRateLimit(loggedReq, "auth_login", async (rateLimitedReq) => {
      try {
        const body = await rateLimitedReq.json();

        // Validate input
        const validatedData = loginSchema.parse(body);
        const { email, password } = validatedData;

        // Find user
        const user = await prisma.user.findUnique({
          where: { email: email.toLowerCase() },
        });

        if (!user || !user.password) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Invalid email or password",
            },
            { status: 401 }
          );
        }

        // Verify password
        const isValidPassword = await AuthService.comparePassword(
          password,
          user.password
        );

        if (!isValidPassword) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Invalid email or password",
            },
            { status: 401 }
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
              username: user.username ?? undefined,
              name: user.name ?? undefined,
              avatarUrl: user.avatarUrl ?? undefined,
              bio: user.bio ?? undefined,
              createdAt: user.createdAt.toISOString(),
              updatedAt: user.updatedAt.toISOString(),
            },
            accessToken,
            refreshToken,
          },
        };

        return NextResponse.json(response);
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
        const { message, statusCode } = sanitizeErrorForClient(error, "login");

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
