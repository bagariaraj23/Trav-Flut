import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { signupSchema } from "@/lib/validation";
import { ApiResponse, AuthResponse } from "@/types/api";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";

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
      } catch (error: any) {
        if (error.name === "ZodError") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: error.errors[0]?.message || "Validation error",
            },
            { status: 400 }
          );
        }
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: "Internal server error",
          },
          { status: 500 }
        );
      }
    });
  });

  return await loggedHandler(request);
}
