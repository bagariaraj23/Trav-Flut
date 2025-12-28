import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowResponse, FollowStatusResponse } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ userId: string }> }
) {
  try {
    const { userId } = await params;
    const followeeId = userId;

    // Verify authentication
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Authorization token required",
        },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);

    if (!payload) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid token",
        },
        { status: 401 }
      );
    }

    const followerId = payload.userId;

    // Get target user's privacy status
    const targetUser = await prisma.user.findUnique({
      where: { id: followeeId },
      select: { isPrivate: true },
    });

    if (!targetUser) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "User not found",
        },
        { status: 404 }
      );
    }

    // Get all relationships in parallel
    const [follow, followRequest, reverseFollow] = await Promise.all([
      prisma.follow.findUnique({
        where: {
          followerId_followeeId: {
            followerId,
            followeeId,
          },
        },
      }),
      prisma.followRequest.findFirst({
        where: {
          followerId,
          followeeId,
          status: "PENDING",
        },
      }),
      prisma.follow.findUnique({
        where: {
          followerId_followeeId: {
            followerId: followeeId,
            followeeId: followerId,
          },
        },
      }),
    ]);

    const followStatus: FollowStatusResponse = {
      isFollowing: !!follow,
      isFollowedBy: !!reverseFollow,
      isRequestPending: !!followRequest,
      isPrivate: targetUser.isPrivate,
      requestId: followRequest?.id,
      requestStatus: followRequest?.status,
    };

    return NextResponse.json<ApiResponse<FollowStatusResponse>>({
      success: true,
      data: followStatus,
    });
  } catch (error: any) {
    console.error("Check follow status error:", error);
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}

// Send follow request or follow user
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ userId: string }> }
) {
  const { userId } = await params;
  const handler = async (req: NextRequest) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const followerId = authenticatedReq.user!.userId;
          const followeeId = userId;

          const result = await prisma.$transaction(async (tx) => {
            // Check followee exists
            const followee = await tx.user.findUnique({
              where: { id: followeeId },
              select: { id: true, isPrivate: true },
            });
            if (!followee) return { code: "NOT_FOUND" };
            if (followerId === followeeId) return { code: "SELF_FOLLOW" };

            // Already following?
            const existingFollow = await tx.follow.findUnique({
              where: {
                followerId_followeeId: {
                  followerId,
                  followeeId,
                },
              },
            });
            if (existingFollow) return { code: "ALREADY_FOLLOW" };

            // Existing pending request?
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
              const followExists = await tx.follow.findUnique({
                where: {
                  followerId_followeeId: {
                    followerId,
                    followeeId,
                  },
                },
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

            // Private: create request, else create follow
            if (followee.isPrivate) {
              const request = await tx.followRequest.create({
                data: { followerId, followeeId, status: "PENDING" },
              });
              return { code: "REQUEST_CREATED", request };
            } else {
              const follow = await tx.follow.create({
                data: { followerId, followeeId },
              });
              return { code: "FOLLOW_CREATED", follow };
            }
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
                success: true,
                message: "Already following this user",
                isFollowing: true,
              },
              { status: 200 }
            );
          }
          if (result.code === "PENDING" && result.request) {
            return NextResponse.json(
              {
                success: true,
                message: "Follow request already pending",
                requestId: result.request.id,
                status: result.request.status,
              },
              { status: 200 }
            );
          }
          if (result.code === "REQUEST_CREATED" && result.request) {
            return NextResponse.json(
              {
                success: true,
                message: "Follow request sent",
                requestId: result.request.id,
                status: result.request.status,
              },
              { status: 201 }
            );
          }
          if (result.code === "FOLLOW_CREATED" && result.follow) {
            return NextResponse.json(
              {
                success: true,
                message: "Followed user successfully",
                followId: result.follow.id,
              },
              { status: 201 }
            );
          }
          return NextResponse.json(
            { success: false, error: "Unknown error" },
            { status: 500 }
          );
        } catch (error: any) {
          if (error.code === "P2002") {
            return NextResponse.json(
              {
                success: false,
                error: "Already following or follow request exists",
              },
              { status: 409 }
            );
          }
          console.error("Follow POST error:", error);
          return NextResponse.json(
            { success: false, error: "Internal server error" },
            { status: 500 }
          );
        }
      });
    });
  };

  return withLogging(handler)(request);
}

// Unfollow a user
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ userId: string }> }
) {
  try {
    const { userId } = await params;
    const followeeId = userId;

    // Verify authentication
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Authorization token required",
        },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);

    if (!payload) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid token",
        },
        { status: 401 }
      );
    }

    const followerId = payload.userId;

    // Handle unfollow in a transaction
    const result = await prisma.$transaction(async (tx) => {
      const deletedRequests = await tx.followRequest.deleteMany({
        where: {
          followerId,
          followeeId,
        },
      });

      // Delete follow relationship
      const deletedFollow = await tx.follow.deleteMany({
        where: {
          followerId,
          followeeId,
        },
      });

      let message = "Successfully unfollowed user";
      if (deletedFollow.count > 0) {
        message = "Successfully unfollowed user";
      } else if (deletedRequests.count > 0) {
        message = "Follow request cancelled successfully";
      } else {
        message = "Already not following this user";
      }

      return {
        success: true,
        message,
        status: 200,
        data: {
          isFollowing: false,
          isRequestPending: false,
        },
      };
    });

    return NextResponse.json<ApiResponse>(result, { status: result.status });
  } catch (error: any) {
    console.error("Unfollow user error:", error);
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
