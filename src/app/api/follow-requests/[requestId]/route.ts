import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowResponse } from "@/types/api";

// Accept or reject a follow request
export async function PATCH(
  request: NextRequest,
  { params }: { params: { requestId: string } }
) {
  try {
    const requestId = params.requestId;
    const body = await request.json();
    const { action } = body; // "accept" or "reject"

    if (!action || !["accept", "reject"].includes(action)) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Action must be 'accept' or 'reject'",
        },
        { status: 400 }
      );
    }

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

    const userId = payload.userId;

    // Find the follow request and verify ownership
    const followRequest = await prisma.followRequest.findUnique({
      where: { id: requestId },
    });

    if (!followRequest) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Follow request not found",
        },
        { status: 404 }
      );
    }

    // Verify that the current user is the receiver of the request
    if (followRequest.receiverId !== userId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "You can only respond to requests sent to you",
        },
        { status: 403 }
      );
    }

    if (followRequest.status !== "PENDING") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "This request has already been processed",
        },
        { status: 400 }
      );
    }

    const newStatus = action === "accept" ? "ACCEPTED" : "REJECTED";

    // Update the request status
    const updatedRequest = await prisma.followRequest.update({
      where: { id: requestId },
      data: {
        status: newStatus,
        updatedAt: new Date(),
      },
    });

    // If accepted, create the follow relationship
    if (action === "accept") {
      const follow = await prisma.follow.create({
        data: {
          followerId: followRequest.senderId,
          followeeId: followRequest.receiverId,
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
          message: "Follow request accepted",
        },
        { status: 200 }
      );
    }

    return NextResponse.json<ApiResponse>({
      success: true,
      message: "Follow request rejected",
    });
  } catch (error: any) {
    console.error("Handle follow request error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}

// Delete/cancel a follow request
export async function DELETE(
  request: NextRequest,
  { params }: { params: { requestId: string } }
) {
  try {
    const requestId = params.requestId;

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

    const userId = payload.userId;

    // Find the follow request and verify ownership
    const followRequest = await prisma.followRequest.findUnique({
      where: { id: requestId },
    });

    if (!followRequest) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Follow request not found",
        },
        { status: 404 }
      );
    }

    // Verify that the current user is either the sender or receiver
    if (followRequest.senderId !== userId && followRequest.receiverId !== userId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "You can only cancel your own requests",
        },
        { status: 403 }
      );
    }

    // Delete the request
    await prisma.followRequest.delete({
      where: { id: requestId },
    });

    return NextResponse.json<ApiResponse>({
      success: true,
      message: "Follow request cancelled",
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
}