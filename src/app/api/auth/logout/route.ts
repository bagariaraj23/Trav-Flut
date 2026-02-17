import { NextRequest, NextResponse } from "next/server";
import { ApiResponse } from "@/types/api";
import { withLogging, withAuth, AuthenticatedRequest, handleApiError } from "@/lib/middleware";
import { AuthService } from "@/lib/auth";
import { revokeAllRefreshTokens } from "@/lib/services/token";
import { PerformanceMonitor } from "@/lib/monitoring";

async function handler(request: AuthenticatedRequest) {
  const endTimer = PerformanceMonitor.getInstance().startTimer("auth_logout");
  try {
    const userId = request.user!.userId;
    const body = await request.json().catch(() => ({}));
    const { refreshToken, logoutAll } = body;
    
    if (logoutAll === true) {
      // Security feature: Logout from all devices
      // Use case: Security breach, lost device, user wants to reset all sessions
      await revokeAllRefreshTokens(userId);
    } else if (refreshToken && typeof refreshToken === "string") {
      // Normal logout: Revoke only the current refresh token
      // This allows user to stay logged in on other devices (better UX)
      await AuthService.revokeRefreshToken(refreshToken);
    } else {
      // If no refresh token provided, still revoke all tokens for security
      // (fallback - should not happen in normal flow, but protects against edge cases)
      await revokeAllRefreshTokens(userId);
    }
    
    endTimer();
    return NextResponse.json<ApiResponse>({
      success: true,
      message: logoutAll 
        ? "Successfully logged out from all devices" 
        : "Successfully logged out",
    });
  } catch (error: any) {
    endTimer();
    return handleApiError(error, {
      endpoint: "POST /auth/logout",
      userId: request.user?.userId,
    });
  }
}

export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    return withAuth(req, handler);
  })(request);
}