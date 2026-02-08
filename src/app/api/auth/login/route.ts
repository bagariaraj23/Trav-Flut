import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { loginSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse } from "@/types/api";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return await withRateLimit(req, "auth_login", async (rateLimitedReq) => {
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
      } catch (error: any) {
        console.error("Login error:", error);
        console.error("Stack trace:", error.stack);

        if (error.name === "ZodError") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: error.errors[0]?.message || "Validation error",
            },
            { status: 400 }
          );
        }

        if (error.name === "PrismaClientKnownRequestError") {
          console.error("Prisma Error:", {
            code: error.code,
            meta: error.meta,
            message: error.message,
          });
        }

        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: "Internal server error: " + error.message,
          },
          { status: 500 }
        );
      }
    });
  });

  return await loggedHandler(request);
}
