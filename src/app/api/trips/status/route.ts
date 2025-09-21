import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, TripResponse } from "@/types/api";

// Get current ongoing trip for user
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

    // Get ongoing trip
    const trip = await prisma.trip.findFirst({
      where: {
        userId,
        status: "ONGOING",
      },
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
    });

    if (!trip) {
      return NextResponse.json<ApiResponse<null>>({
        success: true,
        data: null,
        message: "No ongoing trip found",
      });
    }

    const tripResponse: TripResponse = {
      ...trip,
      startDate: trip.startDate?.toISOString() || undefined,
      endDate: trip.endDate?.toISOString() || undefined,
      coverMediaUrl: trip.coverMediaUrl ?? undefined,
      createdAt: trip.createdAt.toISOString(),
      updatedAt: trip.updatedAt.toISOString(),
      user: trip.user
        ? {
            ...trip.user,
            username: trip.user.username ?? undefined,
            name: trip.user.name ?? undefined,
            avatarUrl: trip.user.avatarUrl ?? undefined,
            bio: trip.user.bio ?? undefined,
            createdAt: trip.user.createdAt.toISOString(),
            updatedAt: trip.user.updatedAt.toISOString(),
          }
        : undefined,
    };

    return NextResponse.json<ApiResponse<TripResponse>>({
      success: true,
      data: tripResponse,
    });
  } catch (error: any) {
    console.error("Get trip status error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
