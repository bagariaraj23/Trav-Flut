import { NextRequest, NextResponse } from "next/server";
import { withAuth, withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { createLike } from "@/lib/services/like";
import { ApiResponse } from "@/types/api";
import { EntityType } from "@prisma/client";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ commentId: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const { commentId } = await params;
          const userId = authenticatedReq.user!.userId;

          await createLike(userId, EntityType.COMMENT, commentId);

          return NextResponse.json<ApiResponse>({
            success: true,
            data: null,
          });
        } catch (error: any) {
          if (error.message === "Entity not found") {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Comment not found",
              },
              { status: 404 }
            );
          }
          return handleApiError(error);
        }
      });
    });
  });
}

