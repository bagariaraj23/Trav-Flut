import { NextRequest, NextResponse } from "next/server";
import { Prisma } from "@prisma/client";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { paginationSchema } from "@/lib/validation";
import { ApiResponse, TripResponse, PaginatedResponse } from "@/types/api";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { PerformanceMonitor, ErrorTracker } from "@/lib/monitoring";

// Get discoverable trips (ongoing and completed trips from followed users and public profiles)
export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "read_hot", async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        const endTimer =
          PerformanceMonitor.getInstance().startTimer("get_discover_trips");

        try {
          const currentUserId = authenticatedReq.user!.userId;
          console.log(`[API] GET /discover/trips - User: ${currentUserId}`);

          const { searchParams } = new URL(authenticatedReq.url);
          const page = searchParams.get("page") || "1";
          const limit = searchParams.get("limit") || "20";
          console.log(
            `[API] GET /discover/trips - Page: ${page}, Limit: ${limit}`
          );

          // Validate pagination parameters
          const paginationData = paginationSchema.parse({
            page: page,
            limit: limit,
          });

          const { page: pageNum, limit: limitNum } = paginationData;
          const offset = (pageNum - 1) * limitNum;
          console.log(`[API] GET /discover/trips - Offset: ${offset}`);

          // Get optional filters
          const status = searchParams.get("status") as
            | "UPCOMING"
            | "ONGOING"
            | "ENDED"
            | null;
          const mood = searchParams.get("mood") as
            | "RELAXED"
            | "ADVENTURE"
            | "SPIRITUAL"
            | "CULTURAL"
            | "PARTY"
            | "MIXED"
            | null;

          console.log(
            `[API] GET /discover/trips - Filters: status=${status}, mood=${mood}`
          );

          // Get list of users that current user is following
          console.log(
            `[API] GET /discover/trips - Fetching followed users for user: ${currentUserId}`
          );
          const followedUsers = await prisma.follow.findMany({
            where: { followerId: currentUserId },
            select: { followeeId: true },
          });

          const followedUserIds = followedUsers.map((f) => f.followeeId);
          console.log(
            `[API] GET /discover/trips - Found ${followedUserIds.length} followed users: ${followedUserIds}`
          );

          // Build where clause for trips
          const whereClause: any = {
            // Exclude current user's own trips from discovery
            userId: { not: currentUserId },
            // Only show ongoing and ended trips (not upcoming)
            status: status ? status : { in: ["ONGOING", "ENDED"] },
            OR: [
              // Trips from followed users
              ...(followedUserIds.length > 0
                ? [
                    {
                      userId: { in: followedUserIds },
                    },
                  ]
                : []),
              // Trips from public users
              {
                user: {
                  isPrivate: false,
                },
              },
            ],
          };

          // Add mood filter if specified
          if (mood) {
            whereClause.mood = mood;
          }

          console.log(
            `[API] GET /discover/trips - Where clause:`,
            JSON.stringify(whereClause, null, 2)
          );

          // Rank in SQL: followed authors, denormalized engagement, ongoing, then recency.
          console.log(`[API] GET /discover/trips - Fetching page and total`);
          const statusSql = status
            ? Prisma.sql`t.status = ${status}::"TripStatus"`
            : Prisma.sql`t.status IN ('ONGOING'::"TripStatus", 'ENDED'::"TripStatus")`;
          const moodSql = mood
            ? Prisma.sql`AND t.mood = ${mood}::"TripMood"`
            : Prisma.empty;
          const audienceSql =
            followedUserIds.length > 0
              ? Prisma.sql`(t."userId" IN (${Prisma.join(followedUserIds)}) OR u."isPrivate" = false)`
              : Prisma.sql`u."isPrivate" = false`;
          const followedRank =
            followedUserIds.length > 0
              ? Prisma.sql`CASE WHEN t."userId" IN (${Prisma.join(followedUserIds)}) THEN 0 ELSE 1 END`
              : Prisma.sql`1`;

          const [totalRows, rankedIds] = await Promise.all([
            prisma.$queryRaw<Array<{ count: bigint }>>`
              SELECT COUNT(*)::bigint AS count
              FROM trips t
              INNER JOIN users u ON u.id = t."userId"
              WHERE t."userId" <> ${currentUserId}
                AND ${statusSql}
                ${moodSql}
                AND ${audienceSql}
            `,
            prisma.$queryRaw<Array<{ id: string }>>`
              SELECT t.id
              FROM trips t
              INNER JOIN users u ON u.id = t."userId"
              WHERE t."userId" <> ${currentUserId}
                AND ${statusSql}
                ${moodSql}
                AND ${audienceSql}
              ORDER BY
                ${followedRank},
                (t."entryCount" + t."participantCount") DESC,
                CASE WHEN t.status = 'ONGOING' THEN 0 ELSE 1 END,
                t."updatedAt" DESC
              LIMIT ${limitNum}
              OFFSET ${offset}
            `,
          ]);
          const totalCount = Number(totalRows[0]?.count ?? 0);
          const orderedIds = rankedIds.map((row) => row.id);
          console.log(`[API] GET /discover/trips - Total count: ${totalCount}`);

          const tripRows =
            orderedIds.length === 0
              ? []
              : await prisma.trip.findMany({
                  where: { id: { in: orderedIds } },
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
                    coverMedia: {
                      select: {
                        id: true,
                        url: true,
                        publicId: true,
                        type: true,
                        filename: true,
                        size: true,
                        width: true,
                        height: true,
                        duration: true,
                        uploadedById: true,
                        tripId: true,
                        createdAt: true,
                      },
                    },
                  },
                });
          const tripById = new Map(tripRows.map((trip) => [trip.id, trip]));
          const trips = orderedIds
            .map((id) => tripById.get(id))
            .filter((trip): trip is (typeof tripRows)[number] => trip != null);

          console.log(
            `[API] GET /discover/trips - Found ${trips.length} trips`
          );

          // Transform to response format
          const tripsResponse: TripResponse[] = trips.map((trip) => ({
            ...trip,
            isFollowing: followedUserIds.includes(trip.userId),
            startDate: trip.startDate?.toISOString() || undefined,
            endDate: trip.endDate?.toISOString() || undefined,
            description: trip.description ?? undefined,
            mood: trip.mood ?? undefined,
            type: trip.type ?? undefined,
            coverMediaId: trip.coverMediaId ?? undefined,
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
            coverMedia: trip.coverMedia
              ? {
                  ...trip.coverMedia,
                  filename: trip.coverMedia.filename ?? undefined,
                  size: trip.coverMedia.size ?? undefined,
                  width: trip.coverMedia.width ?? undefined,
                  height: trip.coverMedia.height ?? undefined,
                  duration: trip.coverMedia.duration ?? undefined,
                  tripId: trip.coverMedia.tripId ?? undefined,
                  createdAt: trip.coverMedia.createdAt.toISOString(),
                }
              : undefined,
          }));

          const hasNext = offset + limitNum < totalCount;
          console.log(`[API] GET /discover/trips - Has next: ${hasNext}`);

          const response: PaginatedResponse<TripResponse> = {
            items: tripsResponse,
            page: pageNum,
            limit: limitNum,
            total: totalCount,
            hasNext,
          };

          console.log(
            `[API] GET /discover/trips - Response: ${tripsResponse.length} trips, page ${pageNum}, hasNext: ${hasNext}`
          );

          return NextResponse.json<
            ApiResponse<PaginatedResponse<TripResponse>>
          >({
            success: true,
            data: response,
          });
        } catch (error: any) {
          console.error(`[API] GET /discover/trips - Error:`, error);
          ErrorTracker.getInstance().trackError(
            error,
            { operation: "get_discover_trips" },
            authenticatedReq.user?.userId
          );
          throw error;
        } finally {
          endTimer();
        }
      });
    });
  });
  
  return await loggedHandler(request);
}
