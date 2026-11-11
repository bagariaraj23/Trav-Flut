import { NextRequest, NextResponse } from "next/server";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";
import { markAllNotificationsRead } from "@/lib/services/notification";
import { ApiResponse } from "@/types/api";

/**
 * PUT /users/me/notifications/read
 * Mark all engagement (LIKE/COMMENT) notifications as read for the current user.
 * Called when the user opens the notifications screen so the badge reflects unread only.
 */
export async function PUT(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const userId = authenticatedReq.user!.userId;
          const count = await markAllNotificationsRead(userId);
          return NextResponse.json<ApiResponse>(
            { success: true, data: { marked: count } },
            { status: 200 }
          );
        } catch (error: unknown) {
          console.error("[API] PUT /users/me/notifications/read error:", error);
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Failed to mark notifications as read" },
            { status: 500 }
          );
        }
      });
    });
  })(request);
}
