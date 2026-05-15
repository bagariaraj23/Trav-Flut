import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, TripResponse } from "@/types/api";
import { TripStatus } from "@prisma/client";

/**
 * Trips visible on a user's profile: trips they own or joined as participant.
 * Respects privacy: private profiles only expose trips to the user themselves or followers.
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: profileUserId } = await params;

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

    const viewerId = payload.userId;

    const profileUser = await prisma.user.findUnique({
      where: { id: profileUserId },
      select: { id: true, isPrivate: true },
    });

    if (!profileUser) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "User not found" },
        { status: 404 }
      );
    }

    if (profileUser.isPrivate && viewerId !== profileUserId) {
      const follow = await prisma.follow.findUnique({
        where: {
          followerId_followeeId: {
            followerId: viewerId,
            followeeId: profileUserId,
          },
        },
      });
      if (!follow) {
        return NextResponse.json<ApiResponse<TripResponse[]>>({
          success: true,
          data: [],
          message: "This profile is private",
        });
      }
    }

    const { searchParams } = new URL(request.url);
    const status = searchParams.get("status") as TripStatus | null;

    const whereClause: {
      OR: Array<
        | { userId: string }
        | { participants: { some: { userId: string } } }
      >;
      status?: TripStatus;
    } = {
      OR: [
        { userId: profileUserId },
        { participants: { some: { userId: profileUserId } } },
      ],
    };

    if (status) {
      whereClause.status = status;
    }

    const trips = await prisma.trip.findMany({
      where: whereClause,
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
        coverMedia: true,
        _count: {
          select: {
            threadEntries: true,
            media: true,
            participants: true,
          },
        },
      },
      orderBy: { createdAt: "desc" },
      take: 50,
    });

    const tripsResponse: TripResponse[] = trips.map((trip) => ({
      ...trip,
      startDate: trip.startDate?.toISOString() ?? undefined,
      endDate: trip.endDate?.toISOString() ?? undefined,
      createdAt: trip.createdAt.toISOString(),
      coverMediaId: trip.coverMediaId ?? undefined,
      type: trip.type ?? undefined,
      mood: trip.mood ?? undefined,
      description: trip.description ?? undefined,
      updatedAt: trip.updatedAt.toISOString(),
      user: trip.user
        ? {
            ...trip.user,
            username: trip.user.username ?? undefined,
            name: trip.user.name ?? undefined,
            avatarUrl: trip.user.avatarUrl ?? undefined,
            bio: trip.user.bio ?? undefined,
            createdAt: trip.user.createdAt.toISOString(),
            updatedAt: trip.user.updatedAt.toISOString(),
          }
        : undefined,
      coverMedia: trip.coverMedia
        ? {
            ...trip.coverMedia,
            filename: trip.coverMedia.filename ?? undefined,
            size: trip.coverMedia.size ?? undefined,
            tripId: trip.coverMedia.tripId ?? undefined,
            createdAt: trip.coverMedia.createdAt.toISOString(),
          }
        : undefined,
    }));

    return NextResponse.json<ApiResponse<TripResponse[]>>({
      success: true,
      data: tripsResponse,
    });
  } catch (error) {
    console.error("GET /users/[id]/trips error:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}
