import { NextRequest, NextResponse } from "next/server";
import { ApiResponse, TripFinalPostResponse } from "@/types/api";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";

function toResponse(
  finalPost: Awaited<ReturnType<typeof TripFinalizerService.publishFinalPost>>
): TripFinalPostResponse {
  return {
    ...finalPost,
    caption: finalPost.caption ?? undefined,
    coverMediaUrl: finalPost.coverMediaUrl ?? undefined,
    publishedAt: finalPost.publishedAt
      ? finalPost.publishedAt.toISOString()
      : undefined,
    createdAt: finalPost.createdAt.toISOString(),
    updatedAt: finalPost.updatedAt.toISOString(),
    generationStatus: finalPost.generationStatus,
  };
}

// Publish final post
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const { id } = await params;
          const tripId = id;
          const userId = authenticatedReq.user!.userId;

          const published = await TripFinalizerService.publishFinalPost(
            tripId,
            userId
          );

          return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
            success: true,
            data: toResponse(published),
            message: "Final post published successfully",
          });
        } catch (error) {
          return handleApiError(error);
        }
      });
    });
  });

  return await loggedHandler(request);
}
