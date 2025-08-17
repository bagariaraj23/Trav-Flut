import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowRequestResponse, PaginatedResponse } from "@/types/api";

// Get pending follow requests for the authenticated user
export async function GET(request: NextRequest) {
  try {
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
    const { searchParams } = new URL(request.url);
    const page = parseInt(searchParams.get("page") || "1");
    const limit = parseInt(searchParams.get("limit") || "20");
    const type = searchParams.get("type") || "received"; // received or sent

    const skip = (page - 1) * limit;

    let whereClause;
    let includeClause;

    if (type === "sent") {
      whereClause = { senderId: userId, status: "PENDING" };
      includeClause = {
        receiver: {
          select: {
            id: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
          },
        },
      };
    } else {
      whereClause = { receiverId: userId, status: "PENDING" };
      includeClause = {
        sender: {
          select: {
            id: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
          },
        },
      };
    }

    const [requests, total] = await Promise.all([
      prisma.followRequest.findMany({
        where: whereClause,
        include: includeClause,
        orderBy: { createdAt: "desc" },
        skip,
        take: limit,
      }),
      prisma.followRequest.count({
        where: whereClause,
      }),
    ]);

    const followRequestResponses: FollowRequestResponse[] = requests.map((request) => ({
      id: request.id,
      senderId: request.senderId,
      receiverId: request.receiverId,
      status: request.status as "PENDING" | "ACCEPTED" | "REJECTED",
      createdAt: request.createdAt.toISOString(),
      updatedAt: request.updatedAt.toISOString(),
      sender: type === "received" && request.sender ? {
        id: request.sender.id,
        email: "", // Don't expose email
        username: request.sender.username,
        name: request.sender.name,
        avatarUrl: request.sender.avatarUrl,
        bio: request.sender.bio,
        isPrivate: false, // Not needed in this context
        createdAt: "",
        updatedAt: "",
      } : undefined,
      receiver: type === "sent" && request.receiver ? {
        id: request.receiver.id,
        email: "", // Don't expose email
        username: request.receiver.username,
        name: request.receiver.name,
        avatarUrl: request.receiver.avatarUrl,
        bio: request.receiver.bio,
        isPrivate: false, // Not needed in this context
        createdAt: "",
        updatedAt: "",
      } : undefined,
    }));

    const response: PaginatedResponse<FollowRequestResponse> = {
      items: followRequestResponses,
      page,
      limit,
      total,
      hasNext: total > page * limit,
    };

    return NextResponse.json<ApiResponse<PaginatedResponse<FollowRequestResponse>>>({
      success: true,
      data: response,
    });
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
}