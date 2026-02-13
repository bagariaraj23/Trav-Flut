import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { signupSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse } from "@/types/api";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { sanitizeErrorForClient } from "@/lib/prismaErrors";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return await withRateLimit(req, "auth_signup", async (rateLimitedReq) => {
      try {
        const body = await rateLimitedReq.json();
        // Validate input
        const validatedData = signupSchema.parse(body);
        const { email, password, name, username } = validatedData;
        // Hash password
        const hashedPassword = await AuthService.hashPassword(password);
        // Try to create user directly; handle unique constraint error
        let user;
        try {
          user = await prisma.user.create({
            data: {
              email: email.toLowerCase(),
              password: hashedPassword,
              name,
              username,
            },
          });
        } catch (error: any) {
          // Use centralized Prisma error mapper for friendly messages
          const { handlePrismaUniqueError } = await import(
            "@/lib/prismaErrors"
          );
          const message = handlePrismaUniqueError(error, {
            email: "User with this email",
            username: "Username",
          });
          if (message) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: message,
              },
              { status: 400 }
            );
          }
          throw error;
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

  return await loggedHandler(request);
}
