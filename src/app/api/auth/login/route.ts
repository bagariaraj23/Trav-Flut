import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { loginSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse } from "@/types/api";
import { withRateLimit, withLogging, withCors, handleApiError } from "@/lib/middleware";
import { sanitizeErrorForClient } from "@/lib/prismaErrors";
import { PerformanceMonitor } from "@/lib/monitoring";

export async function POST(request: NextRequest) {
  return await withCors(async (req) => {
    const loggedHandler = withLogging(async (loggedReq) => {
      return await withRateLimit(loggedReq, "auth_login", async (rateLimitedReq) => {
      const endTimer = PerformanceMonitor.getInstance().startTimer("auth_login");
      try {
        const body = await rateLimitedReq.json();

        // Determine if input is email or username by checking for '@' before validation
        const originalInput = body.email?.trim() || "";
        const isEmail = originalInput.includes("@");

        // Validate input
        const validatedData = loginSchema.parse(body);
        const { email, password } = validatedData;

        // Find user by email or username based on original input type
        const user = isEmail
          ? await prisma.user.findUnique({
              where: { email },
            })
          : await prisma.user.findUnique({
              where: { username: email },
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

        endTimer();
        return NextResponse.json(response);
      } catch (error: unknown) {
        endTimer();
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
