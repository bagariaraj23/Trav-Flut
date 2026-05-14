import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { NotFoundError, AuthorizationError } from "@/lib/errors";
import { AuthService } from "@/lib/auth";
import { createThreadEntrySchema } from "@/lib/validation";
import {
  ApiResponse,
  TripThreadEntryResponse,
  TripThreadEntriesPageResponse,
  PlaceResponse,
} from "@/types/api";
import { serializePlace } from "@/lib/place";
import { checkLikeStatus } from "@/lib/services/like";
import { createNotification } from "@/lib/services/notification";
import { EntityType, Prisma } from "@prisma/client";
import { canViewEntity } from "@/lib/auth/permissions";
import { resolveTaggedUserIdsForTripThread } from "@/lib/services/tripTagResolution";

const THREAD_ENTRY_LIST_INCLUDE = {
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
} as const;

type ThreadEntryListRow = Prisma.TripThreadEntryGetPayload<{
  include: typeof THREAD_ENTRY_LIST_INCLUDE;
}>;

function encodeEntryCursor(createdAt: Date, id: string): string {
  return Buffer.from(
    JSON.stringify({ c: createdAt.toISOString(), i: id })
  ).toString("base64url");
}

function decodeEntryCursor(cursor: string): { createdAt: Date; id: string } {
  const raw = Buffer.from(cursor, "base64url").toString("utf8");
  const obj = JSON.parse(raw) as { c?: string; i?: string };
  if (!obj.c || !obj.i) {
    throw new Error("invalid_cursor");
  }
  return { createdAt: new Date(obj.c), id: obj.i };
}

function mapThreadEntryRowsToResponse(
  entries: ThreadEntryListRow[],
  likeStatusMap: Record<string, boolean>
): (TripThreadEntryResponse & {
  likeCount: number;
  commentCount: number;
  hasLiked: boolean;
})[] {
  return entries.map((entry) => ({
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
    likeCount: entry.likeCount,
    commentCount: entry.commentCount,
    hasLiked: likeStatusMap[entry.id] || false,
    author: {
      ...entry.author,
      createdAt: entry.author.createdAt.toISOString(),
      updatedAt: entry.author.updatedAt.toISOString(),
    },
    taggedUsers:
      entry.taggedUsers && entry.taggedUsers.length > 0
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
}

// Create a new thread entry
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

    let taggedUserIds: string[] = [];
    if (validatedData.taggedUsernames?.length) {
      taggedUserIds = await resolveTaggedUserIdsForTripThread({
        trip: {
          userId: trip.userId,
          participants: trip.participants,
        },
        actorId: userId,
        taggedUsernames: validatedData.taggedUsernames,
      });
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

    let mediaRecord: {
      id: string;
      uploadedById: string;
      tripId: string | null;
    } | null = null;

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
      // Re-validate media inside transaction to avoid TOCTOU: fetch fresh media row
      if (mediaRecord) {
        const txMedia = await tx.media.findUnique({
          where: { id: mediaRecord.id },
          select: { id: true, uploadedById: true, tripId: true },
        });
        if (!txMedia) {
          throw new NotFoundError("Media not found");
        }
        if (txMedia.uploadedById !== userId) {
          throw new AuthorizationError("You do not have permission to use this media");
        }
        if (txMedia.tripId && txMedia.tripId !== tripId) {
          throw new Error("Media is already attached to another trip");
        }

        if (txMedia.tripId !== tripId) {
          await tx.media.update({
            where: { id: mediaRecord.id },
            data: { tripId },
          });
        }
      }
      const entry = await tx.tripThreadEntry.create({
        data: {
          tripId,
          authorId: userId,
          type: validatedData.type,
          contentText: validatedData.contentText,
          locationName: locationName ?? undefined,
          mediaId: mediaRecord
            ? mediaRecord.id
            : validatedData.mediaId ?? undefined,
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
      // Tagging logic inside transaction!
      if (taggedUserIds.length > 0) {
        await tx.tripThreadTag.createMany({
          data: taggedUserIds.map((taggedUserId) => ({
            threadEntryId: entry.id,
            taggedUserId,
          })),
          skipDuplicates: true,
        });
      }
      return entry;
    });

    // Fire-and-forget: create TAG notifications for each tagged user (exclude self)
    const recipientsToNotify = taggedUserIds.filter((id) => id !== userId);
    if (recipientsToNotify.length > 0) {
      void (async () => {
        const contentPreview =
          createdEntry.contentText &&
          createdEntry.contentText.length > 0
            ? createdEntry.contentText.length > 60
              ? createdEntry.contentText.slice(0, 60) + "..."
              : createdEntry.contentText
            : undefined;
        for (const taggedUserId of recipientsToNotify) {
          try {
            const canRecipientView = await canViewEntity(
              taggedUserId,
              EntityType.TRIP_THREAD_ENTRY,
              createdEntry.id
            );
            if (!canRecipientView) {
              continue;
            }
            await createNotification({
              type: "TAG",
              actorId: userId,
              recipientId: taggedUserId,
              entityType: "TRIP_THREAD_ENTRY",
              entityId: createdEntry.id,
              metadata: {
                tagSource: "thread_entry",
                tripId,
                threadEntryId: createdEntry.id,
                postEntityType: "TRIP_THREAD_ENTRY",
                postEntityId: createdEntry.id,
                ...(contentPreview && { contentPreview }),
              },
            });
          } catch (err) {
            console.error(
              "[Notification] Failed to create TAG notification:",
              { tripId, threadEntryId: createdEntry.id, actorId: userId, taggedUserId, error: err }
            );
          }
        }
      })();
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
      taggedUsers:
        completeEntry!.taggedUsers && completeEntry!.taggedUsers.length > 0
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

    const { searchParams } = new URL(request.url);
    const limitRaw = parseInt(searchParams.get("limit") || "30", 10);
    const limit = Math.min(Math.max(Number.isFinite(limitRaw) ? limitRaw : 30, 1), 100);
    const cursorParam = searchParams.get("cursor");

    let whereClause: Prisma.TripThreadEntryWhereInput = { tripId };

    if (cursorParam) {
      let decoded: { createdAt: Date; id: string };
      try {
        decoded = decodeEntryCursor(cursorParam);
      } catch {
        return NextResponse.json<ApiResponse>(
          { success: false, error: "Invalid cursor" },
          { status: 400 }
        );
      }
      whereClause = {
        tripId,
        OR: [
          { createdAt: { lt: decoded.createdAt } },
          {
            AND: [
              { createdAt: decoded.createdAt },
              { id: { lt: decoded.id } },
            ],
          },
        ],
      };
    }

    const rows = await prisma.tripThreadEntry.findMany({
      where: whereClause,
      include: THREAD_ENTRY_LIST_INCLUDE,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: limit + 1,
    });

    const hasMoreOlder = rows.length > limit;
    const pageRows = hasMoreOlder ? rows.slice(0, limit) : rows;
    pageRows.reverse();

    const entryIds = pageRows.map((e) => e.id);
    const likeStatusMap = await checkLikeStatus(
      userId,
      EntityType.TRIP_THREAD_ENTRY,
      entryIds
    );

    const items = mapThreadEntryRowsToResponse(pageRows, likeStatusMap);

    const oldestInPage = pageRows[0] ?? null;
    const pageData: TripThreadEntriesPageResponse = {
      items,
      hasMoreOlder,
      nextOlderCursor:
        hasMoreOlder && oldestInPage
          ? encodeEntryCursor(oldestInPage.createdAt, oldestInPage.id)
          : null,
    };

    return NextResponse.json<ApiResponse<TripThreadEntriesPageResponse>>({
      success: true,
      data: pageData,
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
