import { NextRequest, NextResponse } from "next/server";
import { TripStatus } from "@prisma/client";
import {
  ApiResponse,
  TripFinalPostResponse,
} from "@/types/api";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { prisma } from "@/lib/prisma";
import { ValidationError } from "@/lib/errors";

function toResponse(
  finalPost: Awaited<ReturnType<typeof TripFinalizerService.generateFinalPost>>
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

          const trip = await prisma.trip.findUnique({
            where: { id: tripId },
            select: { userId: true, status: true },
          });

          if (!trip) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Trip not found" },
              { status: 404 }
            );
          }

          if (trip.userId !== userId) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Only the trip owner can generate the final post",
              },
              { status: 403 }
            );
          }

          if (trip.status !== TripStatus.ENDED) {
            throw new ValidationError(
              "Trip must be ended before generating a final post"
            );
          }

          const finalPost = await TripFinalizerService.generateFinalPost(
            tripId,
            userId
          );

          return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
            success: true,
            data: toResponse(finalPost),
            message: "Final post ready",
          });
        } catch (error) {
          return handleApiError(error);
        }
      });
    });
  });

  return await loggedHandler(request);
}
