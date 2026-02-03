import { NextRequest, NextResponse } from "next/server";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { resolveShareToken } from "@/lib/services/share";
import { canViewEntity } from "@/lib/auth/permissions";
import { logSecurityEvent } from "@/lib/security/events";
import { ApiResponse } from "@/types/api";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ shareToken: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      try {
        const { shareToken } = await params;
        const ipAddress = request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || null;

        const result = await resolveShareToken(shareToken);

        const authHeader = request.headers.get('authorization');
        let userId: string | null = null;
        if (authHeader?.startsWith('Bearer ')) {
          const token = authHeader.substring(7);
          const { AuthService } = await import('@/lib/auth');
          const payload = AuthService.verifyAccessToken(token);
          userId = payload?.userId || null;
        }

        const canView = await canViewEntity(userId, result.share.entityType, result.share.entityId);

        if (!canView) {
          await logSecurityEvent({
            eventType: 'UNAUTHORIZED_ACCESS',
            userId,
            entityType: result.share.entityType,
            entityId: result.share.entityId,
            ipAddress,
            metadata: { action: 'resolve_share', shareToken },
          });

          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Entity not found or access denied",
            },
            { status: 404 }
          );
        }

        return NextResponse.json<ApiResponse>({
          success: true,
          data: result,
        });
      } catch (error: any) {
        if (error.message === "Share token not found") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Share token not found",
            },
            { status: 404 }
          );
        }
        if (error.message === "Share token expired") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Share token expired",
            },
            { status: 410 }
          );
        }
        return handleApiError(error);
      }
    });
  });
}

