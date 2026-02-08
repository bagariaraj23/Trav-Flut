import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { ApiResponse, UserStats } from "@/types/api";
import {
  withAuth,
  withRateLimit,
  withLogging,
  AuthenticatedRequest,
} from "@/lib/middleware";
import { PerformanceMonitor, ErrorTracker } from "@/lib/monitoring";

// Get user statistics (trip, follower, and following counts)
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  const loggedHandler = withLogging(async (req: NextRequest) => {
    return withRateLimit(req, async (rateLimitedReq: NextRequest) => {
      return withAuth(
        rateLimitedReq,
        async (authenticatedReq: AuthenticatedRequest) => {
          const endTimer =
            PerformanceMonitor.getInstance().startTimer("get_user_stats");

          try {
            const userId = id;

            // Get follower count
            const followerCount = await prisma.follow.count({
              where: { followeeId: userId },
            });

            // Get following count
            const followingCount = await prisma.follow.count({
              where: { followerId: userId },
            });

            // Get trip count
            const tripCount = await prisma.trip.count({
              where: { userId: userId },
            });

            const stats: UserStats = {
              tripCount,
              followerCount,
              followingCount,
            };

            return NextResponse.json<ApiResponse<UserStats>>({
              success: true,
              data: stats,
            });
          } catch (error: any) {
            // Track the error with more context
            ErrorTracker.getInstance().trackError(
              error,
              {
                operation: "get_user_stats",
                targetUserId: id,
              },
              authenticatedReq.user?.userId
            );
            // Re-throw the error to be handled by the middleware's centralized handler
            throw error;
          } finally {
            // Ensure the performance timer is stopped
            endTimer();
          }
        }
      );
    });
  });

  return await loggedHandler(request);
}
