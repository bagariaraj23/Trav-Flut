import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowResponse, FollowStatusResponse } from "@/types/api";

export async function GET(
  request: NextRequest,
  { params }: { params: { userId: string } }
) {
  try {
    const followeeId = params.userId;

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
  { params }: { params: { userId: string } }
) {
  try {
    const followeeId = params.userId;

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

    // Prevent self-follow
    if (followerId === followeeId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "You cannot follow yourself",
        },
        { status: 400 }
      );
    }

    // Get target user and check if they exist
    const followee = await prisma.user.findUnique({
      where: { id: followeeId },
      select: { id: true, isPrivate: true },
    });

    if (!followee) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "User not found",
        },
        { status: 404 }
      );
    }

    // Handle the follow/request in a transaction
    const result = await prisma.$transaction(async (tx) => {
      // Check if already following
      const existingFollow = await tx.follow.findUnique({
        where: {
          followerId_followeeId: {
            followerId,
            followeeId,
          },
        },
      });

      if (existingFollow) {
        return {
          success: true,
          message: "Already following this user",
          status: 200,
          data: {
            isFollowing: true,
            isRequestPending: false,
          },
        };
      }

      // Check for existing follow request
      const existingRequest = await tx.followRequest.findFirst({
        where: {
          followerId,
          followeeId,
          status: "PENDING",
        },
      });

      if (existingRequest) {
        return {
          success: true,
          message: "Follow request already sent",
          status: 200,
          data: {
            isFollowing: false,
            isRequestPending: true,
            requestId: existingRequest.id,
            requestStatus: existingRequest.status,
          },
        };
      }

      if (followee.isPrivate) {
        // Create a follow request for private accounts
        const request = await tx.followRequest.create({
          data: {
            followerId,
            followeeId,
            status: "PENDING",
          },
        });

        return {
          success: true,
          message: "Follow request sent successfully",
          status: 201,
          data: {
            isFollowing: false,
            isRequestPending: true,
            requestId: request.id,
            requestStatus: request.status,
          },
        };
      } else {
        // Create direct follow for public accounts
        const follow = await tx.follow.create({
          data: {
            followerId,
            followeeId,
          },
        });

        return {
          success: true,
          message: "Successfully followed user",
          status: 201,
          data: {
            id: follow.id,
            followerId: follow.followerId,
            followeeId: follow.followeeId,
            createdAt: follow.createdAt.toISOString(),
            isFollowing: true,
            isRequestPending: false,
          },
        };
      }
    });

    return NextResponse.json<ApiResponse>(result, { status: result.status });
  } catch (error: any) {
    console.error("Follow user error:", error);
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}

// Unfollow a user
export async function DELETE(
  request: NextRequest,
  { params }: { params: { userId: string } }
) {
  try {
    const followeeId = params.userId;

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
      // Delete any pending follow requests first
      const deletedRequests = await tx.followRequest.deleteMany({
        where: {
          followerId,
          followeeId,
          status: "PENDING",
        },
      });

      // Delete follow relationship
      const deletedFollow = await tx.follow.deleteMany({
        where: {
          followerId,
          followeeId,
        },
      });

      let message = "Already not following this user";
      if (deletedFollow.count > 0) {
        message = "Successfully unfollowed user";
      } else if (deletedRequests.count > 0) {
        message = "Follow request cancelled successfully";
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
