import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, TripResponse } from "@/types/api";

// End a trip
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const tripId = id;

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
      include: {
        threadEntries: {
          where: {
            type: "MEDIA",
            mediaId: { not: null },
          },
          include: {
            media: {
              select: {
                id: true,
                url: true,
              },
            },
          },
          orderBy: { createdAt: "asc" },
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

    // Update trip status and create final post
    // Note: We don't modify startDate - it should remain as originally set
    const now = new Date();
    const normalizedEndDate = new Date(Date.UTC(
      now.getUTCFullYear(),
      now.getUTCMonth(),
      now.getUTCDate(),
      0, 0, 0, 0
    ));

    const [updatedTrip, finalPost] = await prisma.$transaction(async (tx) => {
      const trip = await tx.trip.findUnique({
        where: { id: tripId },
        include: {
          threadEntries: {
            include: { 
              media: true 
            },
            orderBy: { createdAt: "asc" },
          },
        },
      });
      if (!trip) throw new Error("Trip not found");

      // Use up-to-date threadEntries from transaction
      const textEntries = trip.threadEntries.filter(
        (entry) => entry.type === "TEXT" && entry.contentText
      );
      const mediaEntries = trip.threadEntries.filter(
        (entry) => entry.type === "MEDIA" && entry.mediaId
      );
      const locationEntries = trip.threadEntries.filter(
        (entry) => entry.type === "LOCATION" && entry.locationName
      );

      // Create a simple summary (in production, this would use AI)
      let summaryText = `Amazing trip to ${trip.destinations.join(", ")}! `;

      if (locationEntries.length > 0) {
        summaryText += `Visited ${locationEntries.length} amazing places. `;
      }

      if (textEntries.length > 0) {
        summaryText += `Shared ${textEntries.length} memorable moments. `;
      }

      if (mediaEntries.length > 0) {
        summaryText += `Captured ${mediaEntries.length} beautiful memories.`;
      }

      // Get curated media (first 6 media entries) - use media relation to get URLs
      const curatedMedia = mediaEntries
        .slice(0, 6)
        .map((entry) => entry.media?.url)
        .filter((url): url is string => Boolean(url));

      const updatedTrip = await tx.trip.update({
        where: { id: tripId },
        data: {
          status: "ENDED",
          endDate: normalizedEndDate,
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
      const finalPost = await tx.tripFinalPost.create({
        data: {
          tripId,
          summaryText,
          curatedMedia,
          caption: `My trip to ${trip.destinations.join(
            ", "
          )} was incredible! 🌟`,
        },
      });
      return [updatedTrip, finalPost];
    });

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
      finalPost: {
        ...finalPost,
        caption: finalPost.caption ?? undefined,
        createdAt: finalPost.createdAt.toISOString(),
      },
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
