import { NextRequest, NextResponse } from "next/server";
import { EntityType, Prisma } from "@prisma/client";
import { ZodError } from "zod";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { patchThreadEntryTextSchema } from "@/lib/validation";
import { ApiResponse, TripThreadEntryResponse, PlaceResponse } from "@/types/api";
import { serializePlace } from "@/lib/place";
import { checkLikeStatus } from "@/lib/services/like";
import {
  cleanupThreadEntryMedia,
  purgeThreadEntryWithClient,
} from "@/lib/services/threadEntryPurge";

function parseAuth(request: NextRequest): { userId: string } | NextResponse {
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
  return { userId: payload.userId };
}

const threadEntrySerializeInclude = {
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

type ThreadEntryForSerialize = Prisma.TripThreadEntryGetPayload<{
  include: typeof threadEntrySerializeInclude;
}>;

function serializeEntry(
  entry: ThreadEntryForSerialize,
  hasLiked: boolean
): TripThreadEntryResponse & {
  likeCount: number;
  commentCount: number;
  hasLiked: boolean;
} {
  return {
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
    hasLiked,
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
  };
}

/** Author or trip owner may delete; trip must be ongoing (same as posting). */
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; entryId: string }> }
) {
  try {
    const auth = parseAuth(request);
    if (auth instanceof NextResponse) return auth;
    const { userId } = auth;
    const { id: tripId, entryId } = await params;

    const entry = await prisma.tripThreadEntry.findUnique({
      where: { id: entryId },
      include: {
        trip: { include: { participants: true } },
      },
    });

    if (!entry || entry.tripId !== tripId) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Thread entry not found" },
        { status: 404 }
      );
    }

    const trip = entry.trip;
    const isOwner = trip.userId === userId;
    const isAuthor = entry.authorId === userId;

    if (!isAuthor && !isOwner) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "You do not have permission to delete this entry" },
        { status: 403 }
      );
    }

    if (trip.status !== "ONGOING") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Entries can only be deleted while the trip is ongoing",
        },
        { status: 400 }
      );
    }

    const { mediaId, mediaPublicId } = await prisma.$transaction(async (tx) =>
      purgeThreadEntryWithClient(tx, tripId, entryId)
    );

    await cleanupThreadEntryMedia(mediaId, mediaPublicId);

    return NextResponse.json<ApiResponse<null>>({
      success: true,
      data: null,
      message: "Thread entry deleted",
    });
  } catch (error) {
    console.error("[API] DELETE thread entry:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}

/** Edit text body only; author or trip owner; trip ongoing. */
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; entryId: string }> }
) {
  try {
    const auth = parseAuth(request);
    if (auth instanceof NextResponse) return auth;
    const { userId } = auth;
    const { id: tripId, entryId } = await params;

    const body = await request.json();
    const { contentText } = patchThreadEntryTextSchema.parse(body);

    const entry = await prisma.tripThreadEntry.findUnique({
      where: { id: entryId },
      include: {
        trip: { include: { participants: true } },
        ...threadEntrySerializeInclude,
      },
    });

    if (!entry || entry.tripId !== tripId) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Thread entry not found" },
        { status: 404 }
      );
    }

    if (entry.type !== "TEXT") {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Only text entries can be edited" },
        { status: 400 }
      );
    }

    const trip = entry.trip;
    const isOwner = trip.userId === userId;
    const isAuthor = entry.authorId === userId;

    if (!isAuthor && !isOwner) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "You do not have permission to edit this entry" },
        { status: 403 }
      );
    }

    if (trip.status !== "ONGOING") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Entries can only be edited while the trip is ongoing",
        },
        { status: 400 }
      );
    }

    const EDIT_WINDOW_MS = 15 * 60 * 1000;
    if (isAuthor) {
      const ageMs = Date.now() - entry.createdAt.getTime();
      if (ageMs > EDIT_WINDOW_MS) {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error:
              "Text entries can only be edited within 15 minutes of posting",
          },
          { status: 400 }
        );
      }
    }

    await prisma.tripThreadEntry.update({
      where: { id: entryId },
      data: { contentText },
    });

    const updated = await prisma.tripThreadEntry.findUnique({
      where: { id: entryId },
      include: threadEntrySerializeInclude,
    });

    if (!updated) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Thread entry not found" },
        { status: 404 }
      );
    }

    const likeMap = await checkLikeStatus(userId, EntityType.TRIP_THREAD_ENTRY, [
      entryId,
    ]);
    const response = serializeEntry(updated, likeMap[entryId] || false);

    return NextResponse.json<ApiResponse<typeof response>>({
      success: true,
      data: response,
    });
  } catch (error: unknown) {
    console.error("[API] PATCH thread entry:", error);
    if (error instanceof ZodError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: error.issues[0]?.message || "Invalid request data" },
        { status: 400 }
      );
    }
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}
