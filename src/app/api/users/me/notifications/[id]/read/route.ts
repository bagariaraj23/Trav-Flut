import { NextRequest, NextResponse } from "next/server";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";
import { markNotificationRead } from "@/lib/services/notification";
import { ApiResponse } from "@/types/api";

/**
 * PUT /users/me/notifications/:id/read
 * Mark a single notification as read. Returns 404 if not found or not owned by user.
 */
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const userId = authenticatedReq.user!.userId;
          const { id } = await params;
          if (!id) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Notification ID is required" },
              { status: 400 }
            );
          }
          const updated = await markNotificationRead(id, userId);
          if (!updated) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Notification not found or already read" },
              { status: 404 }
            );
          }
          return NextResponse.json<ApiResponse>(
            { success: true, data: { marked: true } },
            { status: 200 }
          );
        } catch (error: unknown) {
          console.error("[API] PUT /users/me/notifications/:id/read error:", error);
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Failed to mark notification as read" },
            { status: 500 }
          );
        }
      });
    });
  })(request);
}
