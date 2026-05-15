import { NextRequest, NextResponse } from "next/server";
import { EntityType, Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import {
  ApiResponse,
  PlaceResponse,
  TripThreadEntriesPageResponse,
  TripThreadEntryResponse,
} from "@/types/api";
import { serializePlace } from "@/lib/place";
import { checkLikeStatus } from "@/lib/services/like";

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

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; entryId: string }> }
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
    const { id: tripId, entryId } = await params;

    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        participants: true,
        user: { select: { isPrivate: true } },
      },
    });

    if (!trip) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Trip not found" },
        { status: 404 }
      );
    }

    const isOwner = trip.userId === userId;
    const isParticipant = trip.participants.some((p) => p.userId === userId);
    if (!isOwner && !isParticipant && trip.user?.isPrivate) {
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

    const target = await prisma.tripThreadEntry.findUnique({
      where: { id: entryId },
      include: THREAD_ENTRY_LIST_INCLUDE,
    });
    if (!target || target.tripId !== tripId) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Thread entry not found" },
        { status: 404 }
      );
    }

    const { searchParams } = new URL(request.url);
    const sizeRaw = parseInt(searchParams.get("contextSize") || "25", 10);
    const contextSize = Math.min(
      Math.max(Number.isFinite(sizeRaw) ? sizeRaw : 25, 3),
      60
    );
    const olderTake = Math.floor((contextSize - 1) / 2);
    const newerTake = contextSize - 1 - olderTake;

    const older = await prisma.tripThreadEntry.findMany({
      where: {
        tripId,
        OR: [
          { createdAt: { lt: target.createdAt } },
          {
            AND: [
              { createdAt: target.createdAt },
              { id: { lt: target.id } },
            ],
          },
        ],
      },
      include: THREAD_ENTRY_LIST_INCLUDE,
      orderBy: [{ createdAt: "desc" }, { id: "desc" }],
      take: olderTake,
    });

    const newer = await prisma.tripThreadEntry.findMany({
      where: {
        tripId,
        OR: [
          { createdAt: { gt: target.createdAt } },
          {
            AND: [
              { createdAt: target.createdAt },
              { id: { gt: target.id } },
            ],
          },
        ],
      },
      include: THREAD_ENTRY_LIST_INCLUDE,
      orderBy: [{ createdAt: "asc" }, { id: "asc" }],
      take: newerTake,
    });

    const rows = [...older.reverse(), target, ...newer];
    const oldest = rows[0] ?? null;
    const hasMoreOlder = oldest
      ? !!(await prisma.tripThreadEntry.findFirst({
          where: {
            tripId,
            OR: [
              { createdAt: { lt: oldest.createdAt } },
              {
                AND: [
                  { createdAt: oldest.createdAt },
                  { id: { lt: oldest.id } },
                ],
              },
            ],
          },
          select: { id: true },
        }))
      : false;

    const likeStatusMap = await checkLikeStatus(
      userId,
      EntityType.TRIP_THREAD_ENTRY,
      rows.map((e) => e.id)
    );

    const data: TripThreadEntriesPageResponse = {
      items: mapThreadEntryRowsToResponse(rows, likeStatusMap),
      hasMoreOlder,
      nextOlderCursor:
        hasMoreOlder && oldest
          ? encodeEntryCursor(oldest.createdAt, oldest.id)
          : null,
    };

    return NextResponse.json<ApiResponse<TripThreadEntriesPageResponse>>({
      success: true,
      data,
    });
  } catch (error) {
    console.error("[API] GET thread entry context:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}
