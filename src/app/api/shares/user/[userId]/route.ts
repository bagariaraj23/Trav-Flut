import { NextRequest, NextResponse } from "next/server";
import { withAuth, withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { getSharesByUser } from "@/lib/services/share";
import { ApiResponse } from "@/types/api";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ userId: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const { userId } = await params;
          const currentUserId = authenticatedReq.user!.userId;

          if (userId !== currentUserId) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Forbidden",
              },
              { status: 403 }
            );
          }

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

          const result = await getSharesByUser(userId, cursor, limit);

          return NextResponse.json<ApiResponse>({
            success: true,
            data: result,
          });
        } catch (error) {
          return handleApiError(error);
        }
      });
    });
  });
}

