import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { ApiResponse, TripFinalPostResponse } from "@/types/api";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { NotFoundError, ConflictError } from "@/lib/errors";

function toResponse(finalPost: Awaited<
  ReturnType<typeof TripFinalizerService.publishFinalPost>
>): TripFinalPostResponse {
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
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const { id } = await params;
          const tripId = id;
          const userId = authenticatedReq.user!.userId;

          // Check if trip exists and user is owner
          const trip = await prisma.trip.findUnique({
            where: { id: tripId },
            include: {
              finalPost: true,
            },
          });

          if (!trip) {
            throw new NotFoundError("Trip not found");
          }

          if (trip.userId !== userId) {
            throw new ConflictError("Only trip owner can publish final post");
          }

          if (!trip.finalPost) {
            throw new NotFoundError("Final post not found");
          }

          if (trip.finalPost.isPublished) {
            throw new ConflictError("Final post is already published");
          }

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
  })(request);
}