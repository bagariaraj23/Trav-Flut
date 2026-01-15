import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { paginationSchema } from "@/lib/validation";
import {
  ApiResponse,
  TripFinalPostResponse,
  PaginatedResponse,
} from "@/types/api";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { PerformanceMonitor, ErrorTracker } from "@/lib/monitoring";
import { checkLikeStatus } from "@/lib/services/like";
import { EntityType } from "@prisma/client";

// Get home feed (final posts from followed users and public profiles)
export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        const endTimer =
          PerformanceMonitor.getInstance().startTimer("get_home_feed");

        try {
          const currentUserId = authenticatedReq.user!.userId;
          console.log(`[API] GET /feed/home - User: ${currentUserId}`);

          const { searchParams } = new URL(authenticatedReq.url);
          const page = searchParams.get("page") || "1";
          const limit = searchParams.get("limit") || "20";
          console.log(`[API] GET /feed/home - Page: ${page}, Limit: ${limit}`);

          // Validate pagination parameters
          const paginationData = paginationSchema.parse({
            page: page,
            limit: limit,
          });

          const { page: pageNum, limit: limitNum } = paginationData;
          const offset = (pageNum - 1) * limitNum;
          console.log(`[API] GET /feed/home - Offset: ${offset}`);

          // Get list of users that current user is following
          console.log(
            `[API] GET /feed/home - Fetching followed users for user: ${currentUserId}`
          );
          const followedUsers = await prisma.follow.findMany({
            where: { followerId: currentUserId },
            select: { followeeId: true },
          });

          const followedUserIds = followedUsers.map((f) => f.followeeId);
          console.log(
            `[API] GET /feed/home - Found ${followedUserIds.length} followed users: ${followedUserIds}`
          );

          // Build where clause for final posts
          const whereClause: any = {
            isPublished: true,
            OR: [
              // Posts from current user (always show own posts)
              {
                trip: {
                  userId: currentUserId,
                },
              },
              // Posts from followed users
              ...(followedUserIds.length > 0
                ? [
                    {
                      trip: {
                        userId: { in: followedUserIds },
                      },
                    },
                  ]
                : []),
              // Posts from public users (not private)
              {
                trip: {
                  user: {
                    isPrivate: false,
                  },
                },
              },
            ],
          };

          console.log(
            `[API] GET /feed/home - Where clause:`,
            JSON.stringify(whereClause, null, 2)
          );

          // Get total count for pagination
          console.log(`[API] GET /feed/home - Getting total count`);
          const totalCount = await prisma.tripFinalPost.count({
            where: whereClause,
          });
          console.log(`[API] GET /feed/home - Total count: ${totalCount}`);

          // Get final posts with trip and user details
          console.log(
            `[API] GET /feed/home - Fetching final posts with offset: ${offset}, limit: ${limitNum}`
          );
          const finalPosts = await prisma.tripFinalPost.findMany({
            where: whereClause,
            include: {
              trip: {
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
              },
            },
            orderBy: [{ createdAt: "desc" }, { trip: { updatedAt: "desc" } }],
            skip: offset,
            take: limitNum,
          });

          console.log(
            `[API] GET /feed/home - Found ${finalPosts.length} final posts`
          );

          // Get like status for all posts
          const postIds = finalPosts.map((p) => p.id);
          const likeStatusMap = await checkLikeStatus(
            currentUserId,
            EntityType.TRIP_FINAL_POST,
            postIds
          );

          // Transform to response format with engagement data
          const finalPostsResponse: (TripFinalPostResponse & {
            likeCount: number;
            commentCount: number;
            shareCount: number;
            hasLiked: boolean;
          })[] = finalPosts.map((post) => ({
            id: post.id,
            tripId: post.tripId,
            summaryText: post.summaryText,
            curatedMedia: post.curatedMedia,
            caption: post.caption ?? undefined,
            coverMediaUrl: post.coverMediaUrl ?? undefined,
            generationStatus: post.generationStatus,
            isPublished: post.isPublished,
            publishedAt: post.publishedAt
              ? post.publishedAt.toISOString()
              : undefined,
            createdAt: post.createdAt.toISOString(),
            updatedAt: post.updatedAt.toISOString(),
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            shareCount: post.shareCount,
            hasLiked: likeStatusMap[post.id] || false,
            trip: {
              ...post.trip,
              startDate: post.trip.startDate?.toISOString() || undefined,
              endDate: post.trip.endDate?.toISOString() || undefined,
              description: post.trip.description ?? undefined,
              mood: post.trip.mood ?? undefined,
              type: post.trip.type ?? undefined,
              coverMediaId: post.trip.coverMediaId ?? undefined,
              createdAt: post.trip.createdAt.toISOString(),
              updatedAt: post.trip.updatedAt.toISOString(),
              user: post.trip.user
                ? {
                    ...post.trip.user,
                    username: post.trip.user.username ?? undefined,
                    name: post.trip.user.name ?? undefined,
                    avatarUrl: post.trip.user.avatarUrl ?? undefined,
                    bio: post.trip.user.bio ?? undefined,
                    createdAt: post.trip.user.createdAt.toISOString(),
                    updatedAt: post.trip.user.updatedAt.toISOString(),
                  }
                : undefined,
            },
          }));

          const hasNext = offset + limitNum < totalCount;
          console.log(`[API] GET /feed/home - Has next: ${hasNext}`);

          const response: PaginatedResponse<TripFinalPostResponse> = {
            items: finalPostsResponse,
            page: pageNum,
            limit: limitNum,
            total: totalCount,
            hasNext,
          };

          console.log(
            `[API] GET /feed/home - Response: ${finalPostsResponse.length} posts, page ${pageNum}, hasNext: ${hasNext}`
          );

          return NextResponse.json<
            ApiResponse<PaginatedResponse<TripFinalPostResponse>>
          >({
            success: true,
            data: response,
          });
        } catch (error: any) {
          console.error(`[API] GET /feed/home - Error:`, error);
          ErrorTracker.getInstance().trackError(
            error,
            { operation: "get_home_feed" },
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
