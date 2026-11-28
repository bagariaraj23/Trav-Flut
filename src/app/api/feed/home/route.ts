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
import { visibleFinalPostCommentCounts } from "@/lib/services/comment";
import { decodeFeedCursor, encodeFeedCursor } from "@/lib/feedCursor";
import { EntityType, Prisma } from "@prisma/client";
import { omitHiddenTripSpend } from "@/lib/tripSpendVisibility";
import { feedHiddenUserIds } from "@/lib/services/userSafety";
import {
  directPostAudience,
  loadDirectPostsForFeed,
} from "@/lib/services/userPost";
import { homeFeedWindow, sliceMergedFeed } from "@/lib/homeFeedMerge";
import {
  loadFeedMapPins,
  loadFeedThreadPreviews,
} from "@/lib/feedCardPreview";

// Get home feed (final posts from followed users and public profiles)
export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "read_hot", async (rateLimitedReq) => {
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
          const cursorParam = searchParams.get("cursor");
          let feedCursor: { createdAt: Date; id: string } | null = null;
          if (cursorParam) {
            try {
              feedCursor = decodeFeedCursor(cursorParam);
            } catch {
              return NextResponse.json<ApiResponse>(
                { success: false, error: "Invalid cursor" },
                { status: 400 }
              );
            }
          }
          // A cursor page starts at the cursor. A page number must not skip
          // inside each table: the merge would then drop posts that belong
          // on that page. Each list is read from its top, then sliced.
          const offset = feedCursor ? 0 : (pageNum - 1) * limitNum;
          const take = homeFeedWindow(offset, limitNum);
          console.log(
            `[API] GET /feed/home - Offset: ${offset}, cursor: ${feedCursor ? "yes" : "no"}`
          );

          // Get list of users that current user is following
          console.log(
            `[API] GET /feed/home - Fetching followed users for user: ${currentUserId}`
          );
          const followedUsers = await prisma.follow.findMany({
            where: { followerId: currentUserId },
            select: { followeeId: true },
          });

          const followedUserIds = followedUsers.map((f) => f.followeeId);
          const hiddenUserIds = await feedHiddenUserIds(currentUserId);
          console.log(
            `[API] GET /feed/home - Found ${followedUserIds.length} followed users: ${followedUserIds}`
          );

          // Build where clause for final posts
          const whereClause: any = {
            isPublished: true,
            ...(hiddenUserIds.length > 0
              ? { userId: { notIn: hiddenUserIds } }
              : {}),
            OR: [
              // The viewer's own published recaps
              {
                userId: currentUserId,
              },
              // Recaps from people the viewer follows
              ...(followedUserIds.length > 0
                ? [
                    {
                      userId: { in: followedUserIds },
                    },
                  ]
                : []),
              // Recaps from public profiles
              {
                user: {
                  isPrivate: false,
                },
              },
            ],
          };

          console.log(
            `[API] GET /feed/home - Where clause:`,
            JSON.stringify(whereClause, null, 2)
          );

          const cursorWhere: Prisma.TripFinalPostWhereInput = feedCursor
            ? {
                AND: [
                  whereClause,
                  {
                    OR: [
                      { createdAt: { lt: feedCursor.createdAt } },
                      {
                        AND: [
                          { createdAt: feedCursor.createdAt },
                          { id: { lt: feedCursor.id } },
                        ],
                      },
                    ],
                  },
                ],
              }
            : whereClause;

          // Both audience counts run with the page. A cursor reads the next
          // window from each list. A page number reads each list from the
          // top through offset + limit + 1, then the merge slices the page.
          // Trip entry and participant totals are the denormalized columns.
          console.log(`[API] GET /feed/home - Fetching page and total`);
          const directWhere = directPostAudience(
            currentUserId,
            followedUserIds,
            hiddenUserIds
          );
          const [totalCount, rows, directTotal, directPosts] = await Promise.all([
            prisma.tripFinalPost.count({ where: whereClause }),
            prisma.tripFinalPost.findMany({
              where: cursorWhere,
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
                  },
                },
              },
              orderBy: [{ createdAt: "desc" }, { id: "desc" }],
              skip: 0,
              take,
            }),
            prisma.userPost.count({ where: directWhere }),
            loadDirectPostsForFeed({
              where: directWhere,
              cursor: feedCursor,
              offset: 0,
              limit: take,
              viewerId: currentUserId,
            }),
          ]);
          console.log(
            `[API] GET /feed/home - Trip posts: ${totalCount}, direct posts: ${directTotal}`
          );

          // Trip-post engagement + card previews before merging with direct posts.
          const postIds = rows.map((p) => p.id);
          const tripIds = Array.from(new Set(rows.map((p) => p.tripId)));
          const [likeStatusMap, commentCounts, threadPreviews, mapPinsByTrip] =
            await Promise.all([
              checkLikeStatus(
                currentUserId,
                EntityType.TRIP_FINAL_POST,
                postIds
              ),
              visibleFinalPostCommentCounts(
                rows.map((post) => ({
                  id: post.id,
                  userId: post.userId,
                })),
                currentUserId
              ),
              loadFeedThreadPreviews(tripIds),
              loadFeedMapPins(tripIds),
            ]);

          // Transform trip recaps, then merge them with direct posts by time.
          const tripItems = rows.map((post) => {
            const pins = mapPinsByTrip.get(post.tripId) ?? [];
            return {
              createdAt: post.createdAt,
              id: post.id,
              item: {
                id: post.id,
                tripId: post.tripId,
                postKind: "trip" as const,
                userId: post.userId,
                summaryText: post.summaryText,
                curatedMedia: post.curatedMedia,
                caption: post.caption ?? undefined,
                coverMediaUrl: post.coverMediaUrl ?? undefined,
                templateChoice: post.templateChoice ?? "postcard",
                generationStatus: post.generationStatus,
                isPublished: post.isPublished,
                publishedAt: post.publishedAt
                  ? post.publishedAt.toISOString()
                  : undefined,
                createdAt: post.createdAt.toISOString(),
                updatedAt: post.updatedAt.toISOString(),
                likeCount: post.likeCount,
                commentCount: commentCounts.get(post.id) ?? post.commentCount,
                shareCount: post.shareCount,
                hasLiked: likeStatusMap[post.id] || false,
                threadPreview: threadPreviews.get(post.tripId) ?? [],
                mapPins: pins.length > 0 ? pins : undefined,
                user: post.user
                  ? {
                      ...post.user,
                      username: post.user.username ?? undefined,
                      name: post.user.name ?? undefined,
                      avatarUrl: post.user.avatarUrl ?? undefined,
                      bio: post.user.bio ?? undefined,
                      createdAt: post.user.createdAt.toISOString(),
                      updatedAt: post.user.updatedAt.toISOString(),
                    }
                  : undefined,
                trip: omitHiddenTripSpend(
                  {
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
                  post.trip.userId === currentUserId
                ),
              },
            };
          });

          const mergedPage = sliceMergedFeed(
            [...tripItems, ...directPosts],
            offset,
            limitNum
          );
          const hasNext = mergedPage.hasNext;
          const finalPostsResponse = mergedPage.items.map((entry) => entry.item);

          console.log(`[API] GET /feed/home - Has next: ${hasNext}`);
          const lastPost = finalPostsResponse[finalPostsResponse.length - 1];

          const response: PaginatedResponse<TripFinalPostResponse> = {
            items: finalPostsResponse,
            page: pageNum,
            limit: limitNum,
            total: totalCount + directTotal,
            hasNext,
            nextCursor:
              hasNext && lastPost
                ? encodeFeedCursor(new Date(lastPost.createdAt), lastPost.id)
                : null,
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
  });
  
  return await loggedHandler(request);
}
