import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowResponse } from "@/types/api";

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

    // Check if following
    const existingFollow = await prisma.follow.findUnique({
      where: {
        followerId_followeeId: {
          followerId,
          followeeId,
        },
      },
    });

    // Check for pending follow request
    const pendingRequest = await prisma.followRequest.findUnique({
      where: {
        senderId_receiverId: {
          senderId: followerId,
          receiverId: followeeId,
        },
        status: "PENDING",
      },
    });

    const isFollowing = !!existingFollow;
    const hasPendingRequest = !!pendingRequest;

    return NextResponse.json<ApiResponse<{ 
      isFollowing: boolean; 
      hasPendingRequest: boolean;
    }>>({
      success: true,
      data: { isFollowing, hasPendingRequest },
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

// Follow a user or send follow request
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

    // Check if followee exists and get privacy status
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

    // Check if already following
    const existingFollow = await prisma.follow.findUnique({
      where: {
        followerId_followeeId: {
          followerId,
          followeeId,
        },
      },
    });

    if (existingFollow) {
      return NextResponse.json<ApiResponse>(
        {
          success: true,
          message: "Already following this user",
        },
        { status: 200 }
      );
    }

    // Check if there's already a pending request
    const existingRequest = await prisma.followRequest.findUnique({
      where: {
        senderId_receiverId: {
          senderId: followerId,
          receiverId: followeeId,
        },
      },
    });

    if (existingRequest) {
      if (existingRequest.status === "PENDING") {
        return NextResponse.json<ApiResponse>(
          {
            success: true,
            message: "Follow request already sent",
          },
          { status: 200 }
        );
      } else if (existingRequest.status === "REJECTED") {
        // Update rejected request to pending
        await prisma.followRequest.update({
          where: { id: existingRequest.id },
          data: { 
            status: "PENDING",
            updatedAt: new Date(),
          },
        });

        return NextResponse.json<ApiResponse>(
          {
            success: true,
            message: "Follow request sent",
          },
          { status: 200 }
        );
      }
    }

    // If user is private, create follow request
    if (followee.isPrivate) {
      const followRequest = await prisma.followRequest.create({
        data: {
          senderId: followerId,
          receiverId: followeeId,
          status: "PENDING",
        },
      });

      return NextResponse.json<ApiResponse>(
        {
          success: true,
          message: "Follow request sent",
          data: { requestId: followRequest.id },
        },
        { status: 201 }
      );
    }

    // If user is public, follow immediately
    const follow = await prisma.follow.create({
      data: {
        followerId,
        followeeId,
      },
    });

    const followResponse: FollowResponse = {
      id: follow.id,
      followerId: follow.followerId,
      followeeId: follow.followeeId,
      createdAt: follow.createdAt.toISOString(),
    };

    return NextResponse.json<ApiResponse<FollowResponse>>(
      {
        success: true,
        data: followResponse,
        message: "Successfully followed user",
      },
      { status: 201 }
    );
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

// Unfollow a user or cancel follow request
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

    // Try to delete follow relationship first
    const deletedFollow = await prisma.follow.deleteMany({
      where: {
        followerId,
        followeeId,
      },
    });

    // If no follow relationship existed, try to cancel follow request
    if (deletedFollow.count === 0) {
      const deletedRequest = await prisma.followRequest.deleteMany({
        where: {
          senderId: followerId,
          receiverId: followeeId,
          status: "PENDING",
        },
      });

      if (deletedRequest.count === 0) {
        return NextResponse.json<ApiResponse>(
          {
            success: true,
            message: "No follow relationship or pending request found",
          },
          { status: 200 }
        );
      }

      return NextResponse.json<ApiResponse>({
        success: true,
        message: "Follow request cancelled",
      });
    }

    return NextResponse.json<ApiResponse>({
      success: true,
      message: "Successfully unfollowed user",
    });
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
