import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { createThreadEntrySchema } from "@/lib/validation";
import {
  ApiResponse,
  TripThreadEntryResponse,
  PlaceResponse,
} from "@/types/api";
import { serializePlace } from "@/lib/place";

// Create a new thread entry
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
    const body = await request.json();

    // Validate input
    const validatedData = createThreadEntrySchema.parse(body);

    // If placeId is provided, fetch place details and use its name as locationName if not provided
    let locationName = validatedData.locationName;
    if (validatedData.placeId) {
      const place = await prisma.place.findUnique({
        where: { id: validatedData.placeId },
        select: { id: true, name: true },
      });

      if (!place) {
        return NextResponse.json<ApiResponse>(
          { success: false, error: "Invalid placeId" },
          { status: 400 }
        );
      }

      // Use place name as locationName if not explicitly provided
      if (!locationName) {
        locationName = place.name;
      }
    }

    // Resolve tagged usernames to user IDs
    let taggedUserIds: string[] = [];
    if (
      validatedData.taggedUsernames &&
      validatedData.taggedUsernames.length > 0
    ) {
      const taggedUsers = await prisma.user.findMany({
        where: {
          username: { in: validatedData.taggedUsernames },
        },
        select: { id: true, username: true },
      });

      taggedUserIds = taggedUsers.map((user) => user.id);

      // Log if some usernames weren't found
      const foundUsernames = taggedUsers.map((user) => user.username);
      const notFoundUsernames = validatedData.taggedUsernames.filter(
        (username) => !foundUsernames.includes(username)
      );

      if (notFoundUsernames.length > 0) {
        console.log(
          `[DEBUG] Tagged usernames not found: ${notFoundUsernames.join(", ")}`
        );
      }
    }

    // Check if trip exists and user has access
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        participants: true,
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

    // Check if user is owner or participant
    const isOwner = trip.userId === userId;
    const isParticipant = trip.participants.some((p) => p.userId === userId);

    if (!isOwner && !isParticipant) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Access denied. You must be the trip owner or a participant.",
        },
        { status: 403 }
      );
    }

    if (trip.status !== "ONGOING") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Cannot add entries to a trip that is not ongoing",
        },
        { status: 400 }
      );
    }

    if (validatedData.type === "MEDIA" && !validatedData.mediaId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "mediaId is required for media entries",
        },
        { status: 400 }
      );
    }

    let mediaRecord: { id: string; uploadedById: string; tripId: string | null } | null = null;

    if (validatedData.mediaId) {
      mediaRecord = await prisma.media.findUnique({
        where: { id: validatedData.mediaId },
        select: { id: true, uploadedById: true, tripId: true },
      });

      if (!mediaRecord) {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: "Media not found",
          },
          { status: 404 }
        );
      }

      if (mediaRecord.uploadedById !== userId) {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: "You do not have permission to use this media",
          },
          { status: 403 }
        );
      }

      if (mediaRecord.tripId && mediaRecord.tripId !== tripId) {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: "Media is already attached to another trip",
          },
          { status: 400 }
        );
      }
    }

    const createdEntry = await prisma.$transaction(async (tx) => {
      if (mediaRecord && mediaRecord.tripId !== tripId) {
        await tx.media.update({
          where: { id: mediaRecord.id },
          data: { tripId },
        });
      }

      const entry = await tx.tripThreadEntry.create({
        data: {
          tripId,
          authorId: userId,
          type: validatedData.type,
          contentText: validatedData.contentText,
          locationName: locationName ?? undefined,
          mediaId: mediaRecord ? mediaRecord.id : (validatedData.mediaId ?? undefined),
          gpsCoordinates: validatedData.gpsCoordinates
            ? JSON.stringify(validatedData.gpsCoordinates)
            : undefined,
          placeId: validatedData.placeId ?? undefined,
        },
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
          media: true,
        },
      });

      await tx.trip.update({
        where: { id: tripId },
        data: {
          entryCount: { increment: 1 },
          updatedAt: new Date(),
        },
      });

      return entry;
    });

    // Add tags if provided
    if (taggedUserIds.length > 0) {
      await prisma.tripThreadTag.createMany({
        data: taggedUserIds.map((taggedUserId) => ({
          threadEntryId: createdEntry.id,
          taggedUserId,
        })),
        skipDuplicates: true,
      });
    }

    // Fetch the complete entry with tags and place
    const completeEntry = await prisma.tripThreadEntry.findUnique({
      where: { id: createdEntry.id },
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
        place: true,
      },
    });

    const entryResponse: TripThreadEntryResponse = {
      ...completeEntry!,
      gpsCoordinates: completeEntry!.gpsCoordinates
        ? ((typeof completeEntry!.gpsCoordinates === "string"
            ? JSON.parse(completeEntry!.gpsCoordinates)
            : completeEntry!.gpsCoordinates) as {
            lat: number | null;
            lng: number | null;
          })
        : null,
      createdAt: completeEntry!.createdAt.toISOString(),
      author: {
        ...completeEntry!.author,
        createdAt: completeEntry!.author.createdAt.toISOString(),
        updatedAt: completeEntry!.author.updatedAt.toISOString(),
      },
      taggedUsers: completeEntry!.taggedUsers && completeEntry!.taggedUsers.length > 0
        ? completeEntry!.taggedUsers.map((tag) => ({
            ...tag.taggedUser,
            createdAt: tag.taggedUser.createdAt.toISOString(),
            updatedAt: tag.taggedUser.updatedAt.toISOString(),
          }))
        : [],
      media: completeEntry!.media
        ? {
            ...completeEntry!.media,
            createdAt: completeEntry!.media.createdAt.toISOString(),
          }
        : undefined,
      place: completeEntry!.place
        ? (serializePlace(completeEntry!.place) as PlaceResponse)
        : null,
    };

    return NextResponse.json<ApiResponse<TripThreadEntryResponse>>(
      {
        success: true,
        data: entryResponse,
      },
      { status: 201 }
    );
  } catch (error: any) {
    console.error("Create thread entry error:", error);

    if (error.name === "ZodError") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: error.errors[0]?.message || "Validation error",
        },
        { status: 400 }
      );
    }

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}

// Get trip thread entries
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

    const userId = payload.userId;

    // Check if trip exists and user has access
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        participants: true,
        user: {
          select: { isPrivate: true },
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

    // Check access permissions
    const isOwner = trip.userId === userId;
    const isParticipant = trip.participants.some((p) => p.userId === userId);

    if (!isOwner && !isParticipant) {
      // Check if trip owner's profile is public or if current user follows them
      if (trip.user?.isPrivate) {
        const followRelation = await prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: userId,
              followeeId: trip.userId,
            },
          },
        });

        if (!followRelation) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error:
                "Access denied. This trip belongs to a private profile. Follow the user to view their content.",
            },
            { status: 403 }
          );
        }
      }
    }

    // Get thread entries
    const entries = await prisma.tripThreadEntry.findMany({
      where: { tripId },
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
        place: true,
      },
      orderBy: { createdAt: "asc" },
    });

    const entriesResponse: TripThreadEntryResponse[] = entries.map((entry) => ({
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
      taggedUsers: entry.taggedUsers && entry.taggedUsers.length > 0
        ? entry.taggedUsers.map((tag) => ({
            ...tag.taggedUser,
            createdAt: tag.taggedUser.createdAt.toISOString(),
            updatedAt: tag.taggedUser.updatedAt.toISOString(),
          }))
        : [],
      media: entry.media
        ? {
            ...entry.media,
            createdAt: entry.media.createdAt.toISOString(),
          }
        : undefined,
      place: entry.place
        ? (serializePlace(entry.place) as PlaceResponse)
        : null,
    }));

    return NextResponse.json<ApiResponse<TripThreadEntryResponse[]>>({
      success: true,
      data: entriesResponse,
    });
  } catch (error: any) {
    console.error("Get thread entries error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
