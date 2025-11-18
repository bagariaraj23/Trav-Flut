import { NextRequest, NextResponse } from "next/server";
import { AuthService } from "@/lib/auth";
import { prisma } from "@/lib/prisma";
import {
  ApiResponse,
  TripFinalPostResponse,
  UpdateFinalPostRequest,
} from "@/types/api";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";
import { handleError } from "@/lib/errors";

function toResponse(finalPost: Awaited<
  ReturnType<typeof TripFinalizerService.getFinalPost>
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

export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
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

    const permissionError = await ensureOwner(params.id, payload.userId);
    if (permissionError) {
      return permissionError;
    }

    const finalPost = await TripFinalizerService.getFinalPost(params.id);

    return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
      success: true,
      data: toResponse(finalPost),
    });
  } catch (error) {
    const appError = handleError(error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: appError.message },
      { status: appError.statusCode }
    );
  }
}

export async function PUT(
  request: NextRequest,
  { params }: { params: { id: string } }
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

    const permissionError = await ensureOwner(params.id, payload.userId);
    if (permissionError) {
      return permissionError;
    }

    const body = (await request.json()) as UpdateFinalPostRequest;
    const finalPost = await TripFinalizerService.updateFinalPost(
      params.id,
      body
    );

    return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
      success: true,
      data: toResponse(finalPost),
      message: "Final post updated",
    });
  } catch (error) {
    const appError = handleError(error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: appError.message },
      { status: appError.statusCode }
    );
  }
}