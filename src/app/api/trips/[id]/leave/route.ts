import { NextRequest, NextResponse } from "next/server";
import { ZodError } from "zod";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { leaveTripSchema } from "@/lib/validation";
import { ApiResponse } from "@/types/api";
import {
  cleanupThreadEntryMedia,
  purgeThreadEntryWithClient,
} from "@/lib/services/threadEntryPurge";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Authorization token required" },
        { status: 401 }
      );
    }
    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);
    if (!payload) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Invalid token" },
        { status: 401 }
      );
    }

    const userId = payload.userId;
    const { id: tripId } = await params;

    const body = await request.json();
    const { removeMyData } = leaveTripSchema.parse(body);

    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        participants: { where: { userId } },
      },
    });

    if (!trip) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Trip not found" },
        { status: 404 }
      );
    }

    if (trip.userId === userId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Trip owners cannot leave; transfer ownership or delete the trip",
        },
        { status: 400 }
      );
    }

    if (trip.participants.length === 0) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "You are not a participant on this trip" },
        { status: 400 }
      );
    }

    if (removeMyData && trip.status !== "ONGOING") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error:
            "Your thread entries can only be removed while the trip is ongoing. Leave without removing data, or ask the owner.",
        },
        { status: 400 }
      );
    }

    const mediaCleanups: { mediaId: string | null; mediaPublicId: string | null }[] =
      [];

    await prisma.$transaction(async (tx) => {
      if (removeMyData) {
        const entries = await tx.tripThreadEntry.findMany({
          where: { tripId, authorId: userId },
          select: { id: true },
        });
        for (const { id: entryId } of entries) {
          mediaCleanups.push(
            await purgeThreadEntryWithClient(tx, tripId, entryId)
          );
        }
      }

      await tx.tripParticipant.delete({
        where: {
          tripId_userId: { tripId, userId },
        },
      });

      await tx.trip.update({
        where: { id: tripId },
        data: {
          participantCount: { decrement: 1 },
          updatedAt: new Date(),
        },
      });

      await tx.tripJoinRequest.deleteMany({
        where: {
          tripId,
          receiverId: userId,
          status: "PENDING",
        },
      });
    });

    for (const m of mediaCleanups) {
      await cleanupThreadEntryMedia(m.mediaId, m.mediaPublicId);
    }

    return NextResponse.json<ApiResponse<null>>({
      success: true,
      data: null,
      message: removeMyData
        ? "You left the trip and your entries were removed"
        : "You left the trip",
    });
  } catch (error: unknown) {
    console.error("[API] POST /trips/[id]/leave:", error);
    if (error instanceof ZodError) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: error.issues[0]?.message || "Invalid request body",
        },
        { status: 400 }
      );
    }
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}
