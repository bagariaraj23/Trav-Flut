import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { getConversationMediaContext } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; mediaId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id, mediaId } = await params;
        const sizeParam = authReq.nextUrl.searchParams.get("contextSize");
        const data = await getConversationMediaContext(
          id,
          authReq.user!.userId,
          mediaId,
          sizeParam ? Number(sizeParam) : undefined
        );
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
