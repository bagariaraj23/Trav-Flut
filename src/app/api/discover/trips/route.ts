import { NextRequest, NextResponse } from "next/server";
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
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
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

          // Get total count for pagination
          console.log(`[API] GET /discover/trips - Getting total count`);
          const totalCount = await prisma.trip.count({
            where: whereClause,
          });
          console.log(`[API] GET /discover/trips - Total count: ${totalCount}`);

          // Get trips with user details and counts
          console.log(
            `[API] GET /discover/trips - Fetching trips with offset: ${offset}, limit: ${limitNum}`
          );
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
              _count: {
                select: {
                  threadEntries: true,
                  media: true,
                  participants: true,
                },
              },
            },
            orderBy: [
              // Prioritize ongoing trips
              { status: "asc" },
              { updatedAt: "desc" },
              { createdAt: "desc" },
            ],
            skip: offset,
            take: limitNum,
          });

          console.log(
            `[API] GET /discover/trips - Found ${trips.length} trips`
          );

          // Transform to response format
          const tripsResponse: TripResponse[] = trips.map((trip) => ({
            ...trip,
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
  })(request);
}
