import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  ApiResponse,
  TripFinalPostResponse,
  UpdateFinalPostRequest,
} from "@/types/api";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { ConflictError, NotFoundError } from "@/lib/errors";
import { TripStatus } from "@prisma/client";

function toResponse(
  finalPost: Awaited<ReturnType<typeof TripFinalizerService.getFinalPost>>
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
      status: true,
      participants: {
        where: { userId },
        select: { id: true },
        take: 1,
      },
    },
  });

  if (!trip) {
    return {
      error: NextResponse.json<ApiResponse>(
        { success: false, error: "Trip not found" },
        { status: 404 }
      ),
      trip: null,
    };
  }

  const isOwner = trip.userId === userId;
  const isParticipant = trip.participants.length > 0;

  if (!isOwner && !isParticipant) {
    return {
      error: NextResponse.json<ApiResponse>(
        { success: false, error: "Only trip participants can access final post" },
        { status: 403 }
      ),
      trip: null,
    };
  }

  return { error: null, trip };
}

export async function GET(
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

          const { error, trip } = await ensureParticipantOrOwner(tripId, userId);
          if (error) {
            return error;
          }

          try {
            const finalPost = await TripFinalizerService.getFinalPost(tripId, userId);
            return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
              success: true,
              data: toResponse(finalPost),
            });
          } catch (serviceError) {
            if (!(serviceError instanceof NotFoundError)) {
              throw serviceError;
            }

            if (trip!.status !== TripStatus.ENDED) {
              throw new ConflictError("Trip must be ended before generating final post");
            }

            const generated = await TripFinalizerService.generateFinalPost(tripId, userId);
            return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
              success: true,
              data: toResponse(generated),
            });
          }
        } catch (error) {
          return handleApiError(error);
        }
      });
    });
  });

  return await loggedHandler(request);
}

export async function PUT(
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

          const { error } = await ensureParticipantOrOwner(tripId, userId);
          if (error) {
            return error;
          }

          const body = (await authenticatedReq.json()) as UpdateFinalPostRequest;
          const finalPost = await TripFinalizerService.updateFinalPost(
            tripId,
            userId,
            body
          );

          return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
            success: true,
            data: toResponse(finalPost),
            message: "Final post updated",
          });
        } catch (error) {
          return handleApiError(error);
        }
      });
    });
  });

  return await loggedHandler(request);
}
