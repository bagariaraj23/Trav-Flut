import { NextRequest, NextResponse } from "next/server";
import {
  withRateLimit,
  withLogging,
  handleApiError,
  getOptionalUser,
} from "@/lib/middleware";
import { getCommentReplies } from "@/lib/services/comment";
import { checkLikeStatus } from "@/lib/services/like";
import { ApiResponse } from "@/types/api";
import { EntityType } from "@prisma/client";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ commentId: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
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

        const user = await getOptionalUser(rateLimitedReq);
        if (user && result.items.length > 0) {
          const replyIds = result.items.map((c: { id: string }) => c.id);
          const likedMap = await checkLikeStatus(
            user.userId,
            "COMMENT" as EntityType,
            replyIds
          );
          result.items = result.items.map((item: { id: string }) => ({
            ...item,
            liked: likedMap[item.id] ?? false,
          }));
        }

        return NextResponse.json<ApiResponse>({
          success: true,
          data: result,
        });
      } catch (error) {
        return handleApiError(error);
      }
    });
  });

  return await loggedHandler(request);
}
