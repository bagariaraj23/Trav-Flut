import { NextRequest, NextResponse } from "next/server";
import { AuthService } from "./auth";
import { AppError, AuthenticationError } from "./errors";
import { prisma } from "./prisma";

// Rate limiting is now handled by src/lib/rateLimit.ts

export interface AuthenticatedRequest extends NextRequest {
  user?: {
    userId: string;
    email: string;
  };
}

// Authentication middleware
export async function withAuth(
  request: NextRequest,
  handler: (req: AuthenticatedRequest) => Promise<NextResponse>
): Promise<NextResponse> {
  try {
    const authHeader = request.headers.get("authorization");

    if (!authHeader?.startsWith("Bearer ")) {
      throw new AuthenticationError("Authorization token required");
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);

    if (!payload) {
      throw new AuthenticationError("Invalid or expired token");
    }

    // Verify user still exists and is active
    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
      select: { id: true, email: true, updatedAt: true },
    });

    if (!user) {
      throw new AuthenticationError("User not found");
    }

    // Invalidate tokens issued before the user's last password change/update
    // If token iat is older than user's updatedAt, force re-auth
    // Add 1 second buffer to account for timing precision differences
    if (
      payload.iat &&
      user.updatedAt &&
      payload.iat * 1000 < user.updatedAt.getTime() - 1000
    ) {
      throw new AuthenticationError("Invalid or expired token");
    }

    // Add user to request
    const authenticatedRequest = request as AuthenticatedRequest;
    authenticatedRequest.user = {
      userId: user.id,
      email: user.email,
    };

    return await handler(authenticatedRequest);
  } catch (error) {
    return handleApiError(error);
  }
}

/** Returns the authenticated user from the request or null if not authenticated. */
export async function getOptionalUser(
  request: NextRequest
): Promise<{ userId: string; email: string } | null> {
  try {
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) return null;
    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);
    if (!payload) return null;
    const user = await prisma.user.findUnique({
      where: { id: payload.userId },
      select: { id: true, email: true, updatedAt: true },
    });
    if (!user) return null;
    if (
      payload.iat &&
      user.updatedAt &&
      payload.iat * 1000 < user.updatedAt.getTime() - 1000
    ) {
      return null;
    }
    return { userId: user.id, email: user.email };
  } catch {
    return null;
  }
}

// Rate limiting middleware
// Re-export from centralized rate limit module
export { withRateLimit, withEngagementRateLimit } from "./rateLimit";

// Input validation middleware
export function withValidation<T>(
  schema: any,
  handler: (req: NextRequest, validatedData: T) => Promise<NextResponse>
) {
  return async (request: NextRequest): Promise<NextResponse> => {
    try {
      const body = await request.json();
      const validatedData = schema.parse(body);
      return await handler(request, validatedData);
    } catch (error: any) {
      if (error.name === "ZodError") {
        const errorMessage = error.errors
          .map((e: any) => `${e.path.join(".")}: ${e.message}`)
          .join(", ");
        return handleApiError(new AppError(errorMessage, 400));
      }
      return handleApiError(error);
    }
  };
}

// Error handling middleware
export function handleApiError(error: unknown): NextResponse {
  const appError =
    error instanceof AppError
      ? error
      : new AppError("Internal server error", 500);

  // Log operational errors for monitoring
  if (!appError.isOperational) {
    console.error("Non-operational error:", appError);
  }

  return NextResponse.json(
    {
      success: false,
      error: appError.message,
      ...(process.env.NODE_ENV === "development" && { stack: appError.stack }),
    },
    { status: appError.statusCode }
  );
}

// Security headers middleware
export function withSecurityHeaders(response: NextResponse): NextResponse {
  response.headers.set("X-Content-Type-Options", "nosniff");
  response.headers.set("X-Frame-Options", "DENY");
  response.headers.set("X-XSS-Protection", "1; mode=block");
  response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
  response.headers.set(
    "Permissions-Policy",
    "camera=(), microphone=(), geolocation=()"
  );

  return response;
}

// Request logging middleware
export function withLogging(
  handler: (req: NextRequest) => Promise<NextResponse>
) {
  return async (request: NextRequest): Promise<NextResponse> => {
    const start = Date.now();
    const method = request.method;
    const url = request.url;

    try {
      const response = await handler(request);
      const duration = Date.now() - start;

      console.log(`${method} ${url} - ${response.status} - ${duration}ms`);

      return response;
    } catch (error) {
      const duration = Date.now() - start;
      console.error(`${method} ${url} - ERROR - ${duration}ms`, error);
      throw error;
    }
  };
}
