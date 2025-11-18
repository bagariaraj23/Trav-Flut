import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import {
  ApiResponse,
  TripFinalPostResponse,
  TripResponse,
} from "@/types/api";
import { TripFinalizerService } from "@/lib/services/tripFinalizer";

// End a trip
export async function POST(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const tripId = params.id;

    // Verify authentication
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Authorization token required",
        },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);

    if (!payload) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid token",
        },
        { status: 401 }
      );
    }

    const userId = payload.userId;

    // Check if trip exists and user is owner
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      select: {
        id: true,
        userId: true,
        status: true,
      },
    });

    if (!trip) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Trip not found",
        },
        { status: 404 }
      );
    }

    if (trip.userId !== userId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Only trip owner can end the trip",
        },
        { status: 403 }
      );
    }

    if (trip.status !== "ONGOING") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Trip is not ongoing",
        },
        { status: 400 }
      );
    }

    // Update trip status
    const updatedTrip = await prisma.trip.update({
      where: { id: tripId },
      data: {
        status: "ENDED",
        endDate: new Date(),
        updatedAt: new Date(),
      },
      include: {
        user: {
          select: {
            id: true,
            email: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
            isPrivate: true,
            createdAt: true,
            updatedAt: true,
          },
        },
        _count: {
          select: {
            threadEntries: true,
            media: true,
            participants: true,
          },
        },
        participants: {
          include: {
            user: true,
          },
        },
        threadEntries: {
          include: {
            media: true,
            taggedUsers: true,
            author: true,
          },
          orderBy: { createdAt: "asc" },
        },
      },
    });

    const finalPost = await TripFinalizerService.generateFinalPost(
      tripId,
      userId
    );

    const finalPostResponse: TripFinalPostResponse = {
      ...finalPost,
      caption: finalPost.caption ?? undefined,
      coverMediaUrl: finalPost.coverMediaUrl ?? undefined,
      generationStatus: finalPost.generationStatus,
      publishedAt: finalPost.publishedAt
        ? finalPost.publishedAt.toISOString()
        : undefined,
      createdAt: finalPost.createdAt.toISOString(),
      updatedAt: finalPost.updatedAt.toISOString(),
    };

    const tripResponse: TripResponse = {
      ...updatedTrip,
      startDate: updatedTrip.startDate?.toISOString() || undefined,
      endDate: updatedTrip.endDate?.toISOString() || undefined,
      createdAt: updatedTrip.createdAt.toISOString(),
      updatedAt: updatedTrip.updatedAt.toISOString(),
      user: updatedTrip.user
        ? {
            ...updatedTrip.user,
            username: updatedTrip.user.username ?? undefined,
            name: updatedTrip.user.name ?? undefined,
            avatarUrl: updatedTrip.user.avatarUrl ?? undefined,
            bio: updatedTrip.user.bio ?? undefined,
            createdAt: updatedTrip.user.createdAt.toISOString(),
            updatedAt: updatedTrip.user.updatedAt.toISOString(),
          }
        : undefined,
      finalPost: finalPostResponse,
      description: updatedTrip.description ?? undefined,
      mood: updatedTrip.mood ?? undefined,
      type: updatedTrip.type ?? undefined,
      coverMediaId: updatedTrip.coverMediaId ?? undefined,
      status: updatedTrip.status,
      participants: updatedTrip.participants.map((p: any) => ({
        ...p,
        joinedAt: p.joinedAt.toISOString(),
        user: {
          ...p.user,
          username: p.user.username ?? undefined,
          name: p.user.name ?? undefined,
          avatarUrl: p.user.avatarUrl ?? undefined,
          bio: p.user.bio ?? undefined,
          createdAt: p.user.createdAt.toISOString(),
          updatedAt: p.user.updatedAt.toISOString(),
        },
      })),
      threadEntries: updatedTrip.threadEntries.map((entry: any) => ({
        ...entry,
        createdAt: entry.createdAt.toISOString(),
        author: {
          ...entry.author,
          createdAt: entry.author.createdAt.toISOString(),
          updatedAt: entry.author.updatedAt.toISOString(),
        },
        taggedUsers: entry.taggedUsers.map((tag: any) => ({
          ...tag.taggedUser,
          createdAt: tag.taggedUser.createdAt.toISOString(),
          updatedAt: tag.taggedUser.updatedAt.toISOString(),
        })),
        media: entry.media
          ? {
              ...entry.media,
              createdAt: entry.media.createdAt.toISOString(),
            }
          : undefined,
      })),
      _count: {
        threadEntries: updatedTrip._count.threadEntries,
        media: updatedTrip._count.media,
        participants: updatedTrip._count.participants,
      },
    };

    return NextResponse.json<ApiResponse<TripResponse>>({
      success: true,
      data: tripResponse,
      message: "Trip ended successfully and final post generated",
    });
  } catch (error: any) {
    console.error("End trip error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
