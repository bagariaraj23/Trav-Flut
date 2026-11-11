import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { markConversationRead } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const userId = authReq.user!.userId;
        await markConversationRead(id, userId);
        return NextResponse.json<ApiResponse>(
          { success: true, message: "Marked as read" },
          { status: 200 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
