import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, TripResponse } from "@/types/api";

// Get trip by ID
export async function GET(
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

    const currentUserId = payload.userId;

    // Get trip with full details
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
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
        participants: {
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
          },
        },
        threadEntries: {
          include: {
            author: {
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
            taggedUsers: {
              include: {
                taggedUser: {
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
              },
            },
            media: true,
          },
          orderBy: { createdAt: "asc" },
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

    // Check if user has access to this trip
    const isOwner = trip.userId === currentUserId;
    const isParticipant = trip.participants.some(
      (p) => p.userId === currentUserId
    );

    if (!isOwner && !isParticipant) {
      // Check if trip owner's profile is public or if current user follows them
      if (trip.user?.isPrivate) {
        const followRelation = await prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: currentUserId,
              followeeId: trip.userId,
            },
          },
        });

        if (!followRelation) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error:
                "Access denied. This trip belongs to a private profile. Follow the user to view their trips.",
            },
            { status: 403 }
          );
        }
      }
    }

    const tripResponse: TripResponse = {
      ...trip,
      startDate: trip.startDate?.toISOString() || undefined,
      endDate: trip.endDate?.toISOString() || undefined,
      entryCount: trip.entryCount,
      participantCount: trip.participantCount,
      coverMediaUrl: trip.coverMediaUrl ?? undefined,
      createdAt: trip.createdAt.toISOString(),
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
      participants: trip.participants.map((p) => ({
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
      threadEntries: trip.threadEntries.map((entry) => ({
        ...entry,
        gpsCoordinates: entry.gpsCoordinates
          ? ((typeof entry.gpsCoordinates === "string"
              ? JSON.parse(entry.gpsCoordinates)
              : entry.gpsCoordinates) as {
              lat: number | null;
              lng: number | null;
            })
          : null,
        createdAt: entry.createdAt.toISOString(),
        author: {
          ...entry.author,
          createdAt: entry.author.createdAt.toISOString(),
          updatedAt: entry.author.updatedAt.toISOString(),
        },
        taggedUsers: entry.taggedUsers.map((tag) => ({
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
      finalPost: trip.finalPost
        ? {
            ...trip.finalPost,
            createdAt: trip.finalPost.createdAt.toISOString(),
          }
        : undefined,
    };

    return NextResponse.json<ApiResponse<TripResponse>>({
      success: true,
      data: tripResponse,
    });
  } catch (error: any) {
    console.error("Get trip error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
