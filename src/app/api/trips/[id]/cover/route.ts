import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import { prisma } from "@/lib/prisma";
import {
  withAuth,
  AuthenticatedRequest,
  handleApiError,
} from "@/lib/middleware";
import { ApiResponse, MediaResponse } from "@/types/api";

const updateCoverSchema = z.object({
  coverMediaId: z.string().uuid({
    message: "coverMediaId must be a valid UUID",
  }),
});

async function handler(
  request: AuthenticatedRequest,
  {
    params,
  }: {
    params: { id: string };
  }
) {
  try {
    const tripId = params.id;
    const currentUserId = request.user!.userId;
    const body = await request.json();
    const { coverMediaId } = updateCoverSchema.parse(body);

    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      select: {
        id: true,
        userId: true,
        status: true,
        participants: {
          select: { userId: true },
        },
      },
    });

    if (!trip) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Trip not found" },
        { status: 404 }
      );
    }

    if (trip.status !== "ONGOING") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Trip cover can only be updated while the trip is ongoing",
        },
        { status: 400 }
      );
    }

    const isOwner = trip.userId === currentUserId;
    const isParticipant = trip.participants.some(
      (participant) => participant.userId === currentUserId
    );

    if (!isOwner && !isParticipant) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "You do not have permission to update this trip cover",
        },
        { status: 403 }
      );
    }

    const media = await prisma.media.findUnique({
      where: { id: coverMediaId },
    });

    if (!media) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Media not found" },
        { status: 404 }
      );
    }

    if (media.type !== "IMAGE") {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Trip cover must be an image" },
        { status: 400 }
      );
    }

    if (media.uploadedById !== currentUserId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "You can only use media that you uploaded as a cover",
        },
        { status: 403 }
      );
    }

    if (media.tripId && media.tripId !== tripId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Selected media is already linked to another trip",
        },
        { status: 400 }
      );
    }

    await prisma.media.update({
      where: { id: coverMediaId },
      data: { tripId },
    });

    const updatedTrip = await prisma.trip.update({
      where: { id: tripId },
      data: { coverMediaId },
      include: {
        coverMedia: true,
      },
    });

    const coverMedia: MediaResponse | undefined = updatedTrip.coverMedia
      ? {
          id: updatedTrip.coverMedia.id,
          url: updatedTrip.coverMedia.url,
          type: updatedTrip.coverMedia.type,
          filename: updatedTrip.coverMedia.filename ?? undefined,
          size: updatedTrip.coverMedia.size ?? undefined,
          uploadedById: updatedTrip.coverMedia.uploadedById,
          tripId: updatedTrip.coverMedia.tripId ?? undefined,
          createdAt: updatedTrip.coverMedia.createdAt.toISOString(),
          publicId: updatedTrip.coverMedia.publicId,
        }
      : undefined;

    return NextResponse.json<
      ApiResponse<{ coverMediaId: string | null; coverMedia?: MediaResponse }>
    >({
      success: true,
      message: "Trip cover updated successfully",
      data: {
        coverMediaId: updatedTrip.coverMediaId ?? null,
        coverMedia,
      },
    });
  } catch (error) {
    return handleApiError(error);
  }
}

export async function PATCH(
  request: NextRequest,
  context: { params: { id: string } }
) {
  return withAuth(request, (authRequest) => handler(authRequest, context));
}

