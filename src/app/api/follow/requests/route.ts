import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowRequestDto } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Create a follow request
export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const body = await request.json();
          const { followeeId } = body;
          const followerId = authenticatedReq.user!.userId;

          if (!followeeId) {
            return NextResponse.json(
              { success: false, error: "followeeId is required" },
              { status: 400 }
            );
          }

          const result = await prisma.$transaction(async (tx) => {
            const [follower, followee] = await Promise.all([
              tx.user.findUnique({ where: { id: followerId } }),
              tx.user.findUnique({ where: { id: followeeId } }),
            ]);
            if (!follower || !followee) return { code: "NOT_FOUND" };
            if (followerId === followeeId) return { code: "SELF_FOLLOW" };
            const existingFollow = await tx.follow.findFirst({
              where: { followerId, followeeId },
            });
            if (existingFollow)
              return { code: "ALREADY_FOLLOW", id: existingFollow.id };
            
            // Check for existing pending request
            const existingPendingRequest = await tx.followRequest.findFirst({
              where: { followerId, followeeId, status: "PENDING" },
            });
            if (existingPendingRequest)
              return { code: "PENDING", request: existingPendingRequest };
            
            // Check for ACCEPTED request - if exists, verify follow relationship exists
            // If ACCEPTED request exists but no follow relationship, it's orphaned (user unfollowed)
            // In that case, delete it and allow new request
            const existingAcceptedRequest = await tx.followRequest.findFirst({
              where: { followerId, followeeId, status: "ACCEPTED" },
            });
            if (existingAcceptedRequest) {
              // Verify follow relationship exists - if not, delete orphaned ACCEPTED request
              const followExists = await tx.follow.findFirst({
                where: { followerId, followeeId },
              });
              if (followExists) {
                // Follow relationship exists, so they're already following
                return { code: "ALREADY_FOLLOW" };
              } else {
                // Orphaned ACCEPTED request (user unfollowed), delete it
                await tx.followRequest.deleteMany({
                  where: {
                    followerId,
                    followeeId,
                    status: "ACCEPTED",
                  },
                });
              }
            }
            
            // Delete REJECTED requests to allow re-requesting after rejection
            await tx.followRequest.deleteMany({
              where: {
                followerId,
                followeeId,
                status: "REJECTED",
              },
            });
            
            const followRequest = await tx.followRequest.create({
              data: { followerId, followeeId, status: "PENDING" },
            });
            return { code: "CREATED", request: followRequest };
          });

          if (result.code === "NOT_FOUND") {
            return NextResponse.json(
              { success: false, error: "User not found" },
              { status: 404 }
            );
          }
          if (result.code === "SELF_FOLLOW") {
            return NextResponse.json(
              { success: false, error: "Cannot follow yourself" },
              { status: 400 }
            );
          }
          if (result.code === "ALREADY_FOLLOW") {
            return NextResponse.json(
              {
                success: false,
                error: "Already following this user",
                data: { id: result.id, status: "FOLLOWING" },
              },
              { status: 400 }
            );
          }
          if (result.code === "PENDING" && result.request) {
            return NextResponse.json(
              {
                success: true,
                message: "Follow request already pending",
                data: {
                  id: result.request.id,
                  status: result.request.status,
                  createdAt:
                    typeof result.request.createdAt === "string"
                      ? result.request.createdAt
                      : result.request.createdAt.toISOString(),
                },
              },
              { status: 200 }
            );
          }
          if (result.code === "CREATED" && result.request) {
            return NextResponse.json(
              {
                success: true,
                message: "Follow request sent successfully",
                data: {
                  id: result.request.id,
                  status: result.request.status,
                  createdAt:
                    typeof result.request.createdAt === "string"
                      ? result.request.createdAt
                      : result.request.createdAt.toISOString(),
                },
              },
              { status: 201 }
            );
          }
          // Fallback for any unexpected branch
          return NextResponse.json(
            { success: false, error: "Unknown internal error." },
            { status: 500 }
          );
        } catch (error: any) {
          // Use centralized error handler for unique constraint violations
          const { handlePrismaUniqueError } = await import("@/lib/prismaErrors");
          const uniqueError = handlePrismaUniqueError(error, {
            followerId_followeeId: "Follow request",
          });
          if (uniqueError) {
            return NextResponse.json(
              { success: false, error: uniqueError },
              { status: 409 }
            );
          }
          console.error("Error creating follow request:", error);
          return NextResponse.json(
            { success: false, error: "Internal server error" },
            { status: 500 }
          );
        }
      });
    });
  });
  
  return await loggedHandler(request);
}

// Get all pending follow requests for current user
export async function GET(request: NextRequest) {
  const handler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const userId = authenticatedReq.user!.userId;

          const followRequests = await prisma.followRequest.findMany({
            where: {
              followeeId: userId,
              status: "PENDING",
            },
            include: {
              follower: {
                select: {
                  id: true,
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
            orderBy: {
              createdAt: "desc",
            },
          });

          // Transform the data to match the expected API response format
          const transformedRequests = followRequests.map((request) => ({
            id: request.id,
            followerId: request.followerId,
            followeeId: request.followeeId,
            status: request.status,
            createdAt: request.createdAt.toISOString(),
            updatedAt: request.updatedAt.toISOString(),
            follower: {
              id: request.follower.id,
              username: request.follower.username,
              name: request.follower.name,
              avatarUrl: request.follower.avatarUrl,
              bio: request.follower.bio,
              isPrivate: request.follower.isPrivate,
              createdAt: request.follower.createdAt.toISOString(),
              updatedAt: request.follower.updatedAt.toISOString(),
            },
          }));

          return NextResponse.json<ApiResponse>(
            {
              success: true,
              data: transformedRequests,
            },
            { status: 200 }
          );
        } catch (error: any) {
          console.error("Get follow requests error:", error);
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Internal server error",
            },
            { status: 500 }
          );
        }
      });
    });
  });
  return handler(request);
}

// Delete/cancel a follow request
export async function DELETE(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          const { requestId } = await request.json();

          if (!requestId) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Request ID is required",
              },
              { status: 400 }
            );
          }

          const deletedRequest = await prisma.followRequest.deleteMany({
            where: {
              id: requestId,
              followerId: currentUserId,
            },
          });

          if (deletedRequest.count === 0) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Follow request not found or already processed",
              },
              { status: 404 }
            );
          }

          return NextResponse.json<ApiResponse>({
            success: true,
            message: "Follow request cancelled successfully",
          });
        } catch (error: any) {
          console.error("Cancel follow request error:", error);
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Internal server error",
            },
            { status: 500 }
          );
        }
      });
    });
  });
}
