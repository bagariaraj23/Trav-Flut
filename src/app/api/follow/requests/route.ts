import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowRequestDto } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Create a follow request
export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const body = await request.json();
          const { followeeId } = body;
          const followerId = authenticatedReq.user!.userId;

          // Validate input
          if (!followeeId) {
            return NextResponse.json(
              { success: false, error: "followeeId is required" },
              { status: 400 }
            );
          }

          // Check if users exist
          const [follower, followee] = await Promise.all([
            prisma.user.findUnique({ where: { id: followerId } }),
            prisma.user.findUnique({ where: { id: followeeId } }),
          ]);

          if (!follower || !followee) {
            return NextResponse.json(
              { success: false, error: "User not found" },
              { status: 404 }
            );
          }

          // Prevent self-following
          if (followerId === followeeId) {
            return NextResponse.json(
              { success: false, error: "Cannot follow yourself" },
              { status: 400 }
            );
          }

          // Check if already following
          const existingFollow = await prisma.follow.findFirst({
            where: {
              followerId,
              followeeId: followeeId,
            },
          });

          if (existingFollow) {
            return NextResponse.json(
              {
                success: false,
                error: "Already following this user",
                data: { id: existingFollow.id, status: "FOLLOWING" },
              },
              { status: 400 }
            );
          }

          // Check if follow request already exists
          const existingRequest = await prisma.followRequest.findFirst({
            where: {
              followerId,
              followeeId: followeeId,
              status: "PENDING",
            },
          });

          if (existingRequest) {
            return NextResponse.json(
              {
                success: true,
                message: "Follow request already pending",
                data: {
                  id: existingRequest.id,
                  status: existingRequest.status,
                  createdAt: existingRequest.createdAt,
                },
              },
              { status: 200 }
            );
          }

          // Create follow request
          const followRequest = await prisma.followRequest.create({
            data: {
              followerId,
              followeeId: followeeId,
              status: "PENDING",
            },
          });

          return NextResponse.json(
            {
              success: true,
              message: "Follow request sent successfully",
              data: {
                id: followRequest.id,
                status: followRequest.status,
                createdAt: followRequest.createdAt,
              },
            },
            { status: 201 }
          );
        } catch (error) {
          console.error("Error creating follow request:", error);
          return NextResponse.json(
            { success: false, error: "Internal server error" },
            { status: 500 }
          );
        }
      });
    });
  })(request);
}

// Get all pending follow requests for current user
export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
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
                }
              },
            },
            orderBy: {
              createdAt: "desc",
            },
          });

          // Transform the data to match the expected API response format
          const transformedRequests = followRequests.map(request => ({
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
            }
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
  })(request);
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

          // Find and delete the follow request
          const deletedRequest = await prisma.followRequest.deleteMany({
            where: {
              id: requestId,
              followerId: currentUserId,
              status: "PENDING",
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
  })(request);
}
