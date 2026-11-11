import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import {
  withAuth,
  withRateLimit,
  withLogging,
  handleApiError,
} from "@/lib/middleware";
import { checkLikeStatus } from "@/lib/services/like";
import { EntityType } from "@prisma/client";
import {
  ApiResponse,
  TripFinalPostResponse,
} from "@/types/api";
import { canViewEntity } from "@/lib/auth/permissions";

/**
 * GET /posts/:entityType/:entityId
 * Fetch a single post for deep linking from notifications.
 * Supports TRIP_FINAL_POST. TRIP_THREAD_ENTRY returns 404 (not in feed).
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ entityType: string; entityId: string }> }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, "read_hot", async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const userId = authenticatedReq.user!.userId;
          const { entityType, entityId } = await params;

          if (!entityType || !entityId) {
            return NextResponse.json(
              { success: false, error: "Entity type and ID are required" },
              { status: 400 }
            );
          }

          const type = entityType as EntityType;
          if (type !== "TRIP_FINAL_POST" && type !== "TRIP_THREAD_ENTRY") {
            return NextResponse.json(
              { success: false, error: "Invalid entity type. Supported: TRIP_FINAL_POST, TRIP_THREAD_ENTRY" },
              { status: 400 }
            );
          }

          if (type === "TRIP_THREAD_ENTRY") {
            return NextResponse.json(
              { success: false, error: "Thread entry posts are not supported for direct view" },
              { status: 404 }
            );
          }

          const post = await prisma.tripFinalPost.findUnique({
            where: { id: entityId },
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
          });

          if (!post || !post.isPublished) {
            return NextResponse.json(
              { success: false, error: "Post not found" },
              { status: 404 }
            );
          }

          const allowed = await canViewEntity(
            userId,
            EntityType.TRIP_FINAL_POST,
            post.id
          );
          if (!allowed) {
            return NextResponse.json(
              { success: false, error: "You don't have access to this post" },
              { status: 403 }
            );
          }

          const likeStatusMap = await checkLikeStatus(
            userId,
            EntityType.TRIP_FINAL_POST,
            [post.id]
          );

          const response: TripFinalPostResponse & {
            likeCount: number;
            commentCount: number;
            shareCount: number;
            hasLiked: boolean;
          } = {
            id: post.id,
            tripId: post.tripId,
            userId: post.userId,
            summaryText: post.summaryText,
            curatedMedia: post.curatedMedia,
            caption: post.caption ?? undefined,
            coverMediaUrl: post.coverMediaUrl ?? undefined,
            generationStatus: post.generationStatus,
            isPublished: post.isPublished,
            publishedAt: post.publishedAt?.toISOString() ?? undefined,
            createdAt: post.createdAt.toISOString(),
            updatedAt: post.updatedAt.toISOString(),
            likeCount: post.likeCount,
            commentCount: post.commentCount,
            shareCount: post.shareCount,
            hasLiked: likeStatusMap[post.id] ?? false,
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
            trip: post.trip
              ? {
                  ...post.trip,
                  startDate: post.trip.startDate?.toISOString(),
                  endDate: post.trip.endDate?.toISOString(),
                  description: post.trip.description ?? undefined,
                  mood: post.trip.mood ?? undefined,
                  type: post.trip.type ?? undefined,
                  coverMediaId: post.trip.coverMediaId ?? undefined,
                  createdAt: post.trip.createdAt?.toISOString(),
                  updatedAt: post.trip.updatedAt?.toISOString(),
                  user: post.trip.user
                    ? {
                        ...post.trip.user,
                        username: post.trip.user.username ?? undefined,
                        name: post.trip.user.name ?? undefined,
                        avatarUrl: post.trip.user.avatarUrl ?? undefined,
                        bio: post.trip.user.bio ?? undefined,
                        createdAt: post.trip.user.createdAt?.toISOString(),
                        updatedAt: post.trip.user.updatedAt?.toISOString(),
                      }
                    : undefined,
                }
              : undefined,
          };

          return NextResponse.json<ApiResponse<typeof response>>({
            success: true,
            data: response,
          });
        } catch (error: unknown) {
          return handleApiError(error);
        }
      });
    });
  })(request);
}
