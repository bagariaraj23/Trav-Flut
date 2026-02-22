import { NextRequest, NextResponse } from "next/server";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";
import { getUnreadNotificationCount } from "@/lib/services/notification";
import { ApiResponse } from "@/types/api";

/**
 * GET /users/me/notifications/unread-count
 * Returns unread engagement notification count for badge.
 * Does not include follow requests (counted separately on client).
 */
export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const userId = authenticatedReq.user!.userId;
          const count = await getUnreadNotificationCount(userId);
          return NextResponse.json<ApiResponse>(
            { success: true, data: { count } },
            { status: 200 }
          );
        } catch (error: unknown) {
          console.error("[API] GET /users/me/notifications/unread-count error:", error);
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Failed to fetch notification count" },
            { status: 500 }
          );
        }
      });
    });
  })(request);
}
