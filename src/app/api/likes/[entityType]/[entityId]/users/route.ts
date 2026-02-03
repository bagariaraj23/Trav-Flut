import { NextRequest, NextResponse } from "next/server";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { getLikesByEntity } from "@/lib/services/like";
import { canViewEntity } from "@/lib/auth/permissions";
import { ApiResponse } from "@/types/api";
import { EntityType } from "@prisma/client";
import { AuthService } from "@/lib/auth";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ entityType: string; entityId: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      try {
        const { entityType, entityId } = await params;
        const { searchParams } = new URL(rateLimitedReq.url);

        if (!Object.values(EntityType).includes(entityType as EntityType)) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Invalid entity type",
            },
            { status: 400 }
          );
        }

        const cursor = searchParams.get("cursor") || undefined;
        const limit = parseInt(searchParams.get("limit") || "20", 10);

        if (limit < 1 || limit > 100) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Limit must be between 1 and 100",
            },
            { status: 400 }
          );
        }

        let viewerId: string | null = null;
        const authHeader = req.headers.get("authorization");
        if (authHeader?.startsWith("Bearer ")) {
          try {
            const payload = AuthService.verifyAccessToken(authHeader.slice(7));
            viewerId = payload?.userId ?? null;
          } catch {
            /* invalid token → treat as unauthenticated */
          }
        }

        const canView = await canViewEntity(
          viewerId,
          entityType as EntityType,
          entityId
        );
        if (!canView) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Entity not found or access denied",
            },
            { status: 404 }
          );
        }

        const result = await getLikesByEntity(
          entityType as EntityType,
          entityId,
          cursor,
          limit
        );

        return NextResponse.json<ApiResponse>({
          success: true,
          data: result,
        });
      } catch (error) {
        return handleApiError(error);
      }
    });
  });
}

