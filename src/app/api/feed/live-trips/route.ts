import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { ApiResponse, LiveTripStoryResponse, TripResponse } from "@/types/api";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { PerformanceMonitor } from "@/lib/monitoring";
import { omitHiddenTripSpend } from "@/lib/tripSpendVisibility";

const userSelect = {
  id: true,
  email: true,
  username: true,
  name: true,
  avatarUrl: true,
  bio: true,
  isPrivate: true,
  createdAt: true,
  updatedAt: true,
} as const;

function serializeUser(user: {
  id: string;
  email: string;
  username: string | null;
  name: string | null;
  avatarUrl: string | null;
  bio: string | null;
  isPrivate: boolean;
  createdAt: Date;
  updatedAt: Date;
}) {
  return {
    id: user.id,
    email: user.email,
    username: user.username ?? undefined,
    name: user.name ?? undefined,
    avatarUrl: user.avatarUrl ?? undefined,
    bio: user.bio ?? undefined,
    isPrivate: user.isPrivate,
    createdAt: user.createdAt.toISOString(),
    updatedAt: user.updatedAt.toISOString(),
  };
}

function serializeTrip(
  trip: {
    id: string;
    userId: string;
    title: string;
    description: string | null;
    startDate: Date | null;
    endDate: Date | null;
    destinations: string[];
    mood: TripResponse["mood"];
    type: TripResponse["type"];
    coverMediaId: string | null;
    status: TripResponse["status"];
    entryCount: number;
    participantCount: number;
    createdAt: Date;
    updatedAt: Date;
    user: Parameters<typeof serializeUser>[0] | null;
    coverMedia: {
      id: string;
      url: string;
      type: "IMAGE" | "VIDEO" | "AUDIO" | "GIF";
      filename: string | null;
      size: number | null;
      tripId: string | null;
      uploadedById: string;
      createdAt: Date;
    } | null;
    _count: {
      threadEntries: number;
      media: number;
      participants: number;
    };
    participants: Array<{ userId: string }>;
  },
  currentUserId: string
): TripResponse {
  const viewerIsMember =
    trip.userId === currentUserId ||
    trip.participants.some((p) => p.userId === currentUserId);

  return omitHiddenTripSpend(
    {
      id: trip.id,
      userId: trip.userId,
      title: trip.title,
      description: trip.description ?? undefined,
      startDate: trip.startDate?.toISOString() || undefined,
      endDate: trip.endDate?.toISOString() || undefined,
      destinations: trip.destinations,
      mood: trip.mood ?? undefined,
      type: trip.type ?? undefined,
      coverMediaId: trip.coverMediaId ?? undefined,
      status: trip.status,
      entryCount: trip.entryCount,
      participantCount: trip.participantCount,
      createdAt: trip.createdAt.toISOString(),
      updatedAt: trip.updatedAt.toISOString(),
      user: trip.user ? serializeUser(trip.user) : undefined,
      coverMedia: trip.coverMedia
        ? {
            id: trip.coverMedia.id,
            url: trip.coverMedia.url,
            type: trip.coverMedia.type,
            filename: trip.coverMedia.filename ?? undefined,
            size: trip.coverMedia.size ?? undefined,
            tripId: trip.coverMedia.tripId ?? undefined,
            uploadedById: trip.coverMedia.uploadedById,
            createdAt: trip.coverMedia.createdAt.toISOString(),
          }
        : undefined,
      _count: trip._count,
    },
    viewerIsMember
  );
}

/**
 * Story-style live trips for Home:
 * - current user's ongoing trip (owned or participating)
 * - followed users who own or participate in a visible ongoing trip
 *
 * A trip is "public"/visible when the viewer is on it, follows the owner,
 * or the owner profile is public.
 */
export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        const endTimer =
          PerformanceMonitor.getInstance().startTimer("get_live_trips");

        try {
          const currentUserId = authenticatedReq.user!.userId;

          const [me, followedUsers] = await Promise.all([
            prisma.user.findUnique({
              where: { id: currentUserId },
              select: userSelect,
            }),
            prisma.follow.findMany({
              where: { followerId: currentUserId },
              select: { followeeId: true },
            }),
          ]);

          if (!me) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "User not found" },
              { status: 404 }
            );
          }

          const followedUserIds = followedUsers.map((f) => f.followeeId);
          const followedSet = new Set(followedUserIds);

          const trips = await prisma.trip.findMany({
            where: {
              status: "ONGOING",
              OR: [
                { userId: currentUserId },
                { participants: { some: { userId: currentUserId } } },
                ...(followedUserIds.length > 0
                  ? [
                      { userId: { in: followedUserIds } },
                      {
                        participants: {
                          some: { userId: { in: followedUserIds } },
                        },
                      },
                    ]
                  : []),
              ],
            },
            include: {
              user: { select: userSelect },
              participants: {
                include: { user: { select: userSelect } },
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
            orderBy: { updatedAt: "desc" },
            take: 60,
          });

          const isVisible = (trip: (typeof trips)[number]) => {
            if (trip.userId === currentUserId) return true;
            if (trip.participants.some((p) => p.userId === currentUserId)) {
              return true;
            }
            if (followedSet.has(trip.userId)) return true;
            if (trip.user && !trip.user.isPrivate) return true;
            return false;
          };

          const visible = trips.filter(isVisible);

          type StoryDraft = {
            user: (typeof trips)[number]["user"] | NonNullable<typeof me>;
            trip: (typeof trips)[number];
            isSelf: boolean;
          };

          const byUserId = new Map<string, StoryDraft>();

          const selfOwned = visible.find((t) => t.userId === currentUserId);
          const selfParticipating = visible.find((t) =>
            t.participants.some((p) => p.userId === currentUserId)
          );
          const selfTrip = selfOwned ?? selfParticipating;
          if (selfTrip) {
            byUserId.set(currentUserId, {
              user: me,
              trip: selfTrip,
              isSelf: true,
            });
          }

          for (const followeeId of followedUserIds) {
            if (byUserId.has(followeeId)) continue;

            const owned = visible.find((t) => t.userId === followeeId);
            if (owned?.user) {
              byUserId.set(followeeId, {
                user: owned.user,
                trip: owned,
                isSelf: false,
              });
              continue;
            }

            const asParticipant = visible.find((t) =>
              t.participants.some((p) => p.userId === followeeId)
            );
            const participantUser = asParticipant?.participants.find(
              (p) => p.userId === followeeId
            )?.user;
            if (asParticipant && participantUser) {
              byUserId.set(followeeId, {
                user: participantUser,
                trip: asParticipant,
                isSelf: false,
              });
            }
          }

          const ordered = [...byUserId.values()].sort((a, b) => {
            if (a.isSelf && !b.isSelf) return -1;
            if (!a.isSelf && b.isSelf) return 1;
            return (
              b.trip.updatedAt.getTime() - a.trip.updatedAt.getTime()
            );
          });

          const items: LiveTripStoryResponse[] = ordered.map((story) => ({
            isSelf: story.isSelf,
            user: serializeUser(story.user),
            trip: serializeTrip(story.trip, currentUserId),
          }));

          return NextResponse.json<ApiResponse<LiveTripStoryResponse[]>>({
            success: true,
            data: items,
          });
        } catch (error: unknown) {
          return handleApiError(error, {
            endpoint: "GET /feed/live-trips",
          });
        } finally {
          endTimer();
        }
      });
    });
  });

  return await loggedHandler(request);
}
