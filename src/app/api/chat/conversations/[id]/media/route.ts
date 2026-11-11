import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { listConversationMedia } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const limitParam = authReq.nextUrl.searchParams.get("limit");
        const cursor = authReq.nextUrl.searchParams.get("cursor") ?? undefined;
        const data = await listConversationMedia(id, authReq.user!.userId, {
          limit: limitParam ? Number(limitParam) : undefined,
          cursor,
        });
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
