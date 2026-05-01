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

async function ensureOwner(tripId: string, userId: string) {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: { userId: true },
  });

  if (!trip) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Trip not found" },
      { status: 404 }
    );
  }

  if (trip.userId !== userId) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Only the trip owner can edit the final post" },
      { status: 403 }
    );
  }

  return null;
}

/** Owner or participant may view final post draft; only owner may edit (PUT). */
async function ensureCanReadFinalPost(tripId: string, userId: string) {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    select: {
      userId: true,
      participants: { select: { userId: true } },
    },
  });

  if (!trip) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Trip not found" },
      { status: 404 }
    );
  }

  const isOwner = trip.userId === userId;
  const isParticipant = trip.participants.some((p) => p.userId === userId);
  if (!isOwner && !isParticipant) {
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "You do not have access to this trip's final post",
      },
      { status: 403 }
    );
  }

  return null;
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

          const permissionError = await ensureCanReadFinalPost(tripId, userId);
          if (permissionError) {
            return permissionError;
          }

          const finalPost = await TripFinalizerService.getFinalPost(tripId);

          return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
            success: true,
            data: toResponse(finalPost),
          });
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
  const handler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const { id } = await params;
          const tripId = id;
          const userId = authenticatedReq.user!.userId;

          const permissionError = await ensureOwner(tripId, userId);
          if (permissionError) {
            return permissionError;
          }

          const body =
            (await authenticatedReq.json()) as UpdateFinalPostRequest;
          const finalPost = await TripFinalizerService.updateFinalPost(
            tripId,
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
  return handler(request);
}
