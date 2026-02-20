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
import { AuthorizationError, NotFoundError } from "@/lib/errors";

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

async function ensureParticipantOrOwner(tripId: string, userId: string) {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: {
      id: true,
      userId: true,
      participants: {
        where: { userId },
        select: { id: true },
        take: 1,
      },
    },
  });

  if (!trip) {
    throw new NotFoundError("Trip not found");
  }

  const isOwner = trip.userId === userId;
  const isParticipant = trip.participants.length > 0;

  if (!isOwner && !isParticipant) {
    throw new AuthorizationError("Only trip participants can publish final post");
  }
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

          await ensureParticipantOrOwner(tripId, userId);

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
