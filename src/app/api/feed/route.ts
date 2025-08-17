import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, PaginatedResponse, TripResponse } from "@/types/api";

// Get feed with published final posts
export async function GET(request: NextRequest) {
  try {
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
    const { searchParams } = new URL(request.url);
    const page = parseInt(searchParams.get("page") || "1");
    const limit = Math.min(parseInt(searchParams.get("limit") || "20"), 50);

    const skip = (page - 1) * limit;

    // Get users that the current user follows
    const following = await prisma.follow.findMany({
      where: { followerId: userId },
      select: { followeeId: true },
    });

    const followingIds = following.map(f => f.followeeId);

    // Get trips with published final posts from:
    // 1. Users the current user follows
    // 2. Public users (not private)
    // 3. Exclude the current user's own trips from the feed
    const [trips, total] = await Promise.all([
      prisma.trip.findMany({
        where: {
          AND: [
            {
              finalPost: {
                isPublished: true,
              },
            },
            {
              OR: [
                // Posts from followed users
                { userId: { in: followingIds } },
                // Posts from public users (not private)
                {
                  user: {
                    isPrivate: false,
                    id: { not: userId }, // Exclude current user
                  },
                },
              ],
            },
          ],
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
          finalPost: true,
          _count: {
            select: {
              threadEntries: true,
              media: true,
              participants: true,
            },
          },
        },
        orderBy: [
          { finalPost: { createdAt: "desc" } }, // Most recent final posts first
          { updatedAt: "desc" },
        ],
        skip,
        take: limit,
      }),
      prisma.trip.count({
        where: {
          AND: [
            {
              finalPost: {
                isPublished: true,
              },
            },
            {
              OR: [
                { userId: { in: followingIds } },
                {
                  user: {
                    isPrivate: false,
                    id: { not: userId },
                  },
                },
              ],
            },
          ],
        },
      }),
    ]);

    const tripResponses: TripResponse[] = trips.map((trip) => ({
      id: trip.id,
      userId: trip.userId,
      title: trip.title,
      description: trip.description,
      startDate: trip.startDate?.toISOString(),
      endDate: trip.endDate?.toISOString(),
      destinations: trip.destinations,
      mood: trip.mood as any,
      type: trip.type as any,
      coverMediaUrl: trip.coverMediaUrl,
      status: trip.status as any,
      createdAt: trip.createdAt.toISOString(),
      updatedAt: trip.updatedAt.toISOString(),
      user: trip.user ? {
        id: trip.user.id,
        email: trip.user.email,
        username: trip.user.username,
        name: trip.user.name,
        avatarUrl: trip.user.avatarUrl,
        bio: trip.user.bio,
        isPrivate: trip.user.isPrivate,
        createdAt: trip.user.createdAt.toISOString(),
        updatedAt: trip.user.updatedAt.toISOString(),
      } : undefined,
      finalPost: trip.finalPost ? {
        id: trip.finalPost.id,
        tripId: trip.finalPost.tripId,
        summaryText: trip.finalPost.summaryText,
        curatedMedia: trip.finalPost.curatedMedia,
        caption: trip.finalPost.caption,
        isPublished: trip.finalPost.isPublished,
        createdAt: trip.finalPost.createdAt.toISOString(),
      } : undefined,
      _count: trip._count,
    }));

    const response: PaginatedResponse<TripResponse> = {
      items: tripResponses,
      page,
      limit,
      total,
      hasNext: total > page * limit,
    };

    return NextResponse.json<ApiResponse<PaginatedResponse<TripResponse>>>({
      success: true,
      data: response,
    });
  } catch (error: any) {
    console.error("Get feed error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}