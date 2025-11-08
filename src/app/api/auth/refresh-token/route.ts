import { NextRequest, NextResponse } from 'next/server'
import { AuthService } from '@/lib/auth'
import { ApiResponse } from '@/types/api'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { refreshToken } = body;

    if (!refreshToken) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Refresh token is required",
        },
        { status: 400 }
      );
    }

    // Validate refresh token
    const user = await AuthService.validateRefreshToken(refreshToken);

    if (!user) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid or expired refresh token",
        },
        { status: 401 }
      );
    }

    // ✅ Generate BOTH new access token AND new refresh token
    const newAccessToken = AuthService.generateAccessToken(user);
    const newRefreshToken = AuthService.generateRefreshToken(user);

    // ✅ Store new refresh token (refresh token rotation - security best practice)
    await AuthService.storeRefreshToken(user.id, newRefreshToken);

    // ✅ Return BOTH tokens
    const response: ApiResponse<{ accessToken: string; refreshToken: string }> =
      {
        success: true,
        data: {
          accessToken: newAccessToken,
          refreshToken: newRefreshToken, // ✅ CRITICAL FIX
        },
      };

    return NextResponse.json(response);
  } catch (error: any) {
    console.error("Refresh token error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
