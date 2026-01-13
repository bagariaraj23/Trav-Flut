import { NextRequest, NextResponse } from "next/server";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { getCommentReplies } from "@/lib/services/comment";
import { ApiResponse } from "@/types/api";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ commentId: string }> }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      try {
        const { commentId } = await params;
        const { searchParams } = new URL(rateLimitedReq.url);

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

        const result = await getCommentReplies(commentId, cursor, limit);

        return NextResponse.json<ApiResponse>({
          success: true,
          data: result,
        });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}

