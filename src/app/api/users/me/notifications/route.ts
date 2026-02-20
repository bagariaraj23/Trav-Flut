import { NextRequest, NextResponse } from "next/server";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";
import { getMergedNotifications } from "@/lib/services/notification";
import { ApiResponse } from "@/types/api";

/**
 * GET /users/me/notifications
 * Returns merged notifications: follow requests + like + comment.
 * Reuses same shape as follow-request flow. Sorted by createdAt desc.
 */
export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const userId = authenticatedReq.user!.userId;
          const { searchParams } = new URL(rateLimitedReq.url);
          const limit = Math.min(
            Math.max(parseInt(searchParams.get("limit") || "30", 10), 1),
            50
          );
          const cursor = searchParams.get("cursor") || undefined;

          const { items, hasMore, nextCursor } = await getMergedNotifications(
            userId,
            limit,
            cursor
          );

          return NextResponse.json<ApiResponse>(
            {
              success: true,
              data: { items, hasMore, nextCursor },
            },
            { status: 200 }
          );
        } catch (error: unknown) {
          console.error("[API] GET /users/me/notifications error:", error);
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Failed to load notifications" },
            { status: 500 }
          );
        }
      });
    });
  })(request);
}
