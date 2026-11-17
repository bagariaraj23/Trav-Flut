import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse } from "@/types/api";
import { isProfileUnavailable, viewerHasBlocked } from "@/lib/services/userSafety";

export interface ProfilePostItem {
  id: string;
  tripId: string;
  summaryText: string;
  caption?: string;
  coverMediaUrl?: string;
  publishedAt?: string;
}

/**
 * Published final posts on a profile. Restrict does not remove them here.
 * Home, Discover, and search still omit the restrictor's posts.
 */
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id: profileUserId } = await params;

    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Authorization token required" },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);
    if (!payload) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Invalid token" },
        { status: 401 }
      );
    }

    const viewerId = payload.userId;
    const profileUser = await prisma.user.findUnique({
      where: { id: profileUserId },
      select: { id: true, isPrivate: true },
    });
    if (!profileUser) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "User not found" },
        { status: 404 }
      );
    }
    if (await isProfileUnavailable(profileUserId, viewerId)) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "User not found" },
        { status: 404 }
      );
    }
    if (await viewerHasBlocked(viewerId, profileUserId)) {
      return NextResponse.json<ApiResponse<ProfilePostItem[]>>({
        success: true,
        data: [],
      });
    }
    if (profileUser.isPrivate && viewerId !== profileUserId) {
      const follow = await prisma.follow.findUnique({
        where: {
          followerId_followeeId: {
            followerId: viewerId,
            followeeId: profileUserId,
          },
        },
      });
      if (!follow) {
        return NextResponse.json<ApiResponse<ProfilePostItem[]>>({
          success: true,
          data: [],
          message: "This profile is private",
        });
      }
    }

    const posts = await prisma.tripFinalPost.findMany({
      where: { userId: profileUserId, isPublished: true },
      orderBy: [{ publishedAt: "desc" }, { id: "desc" }],
      take: 50,
      select: {
        id: true,
        tripId: true,
        summaryText: true,
        caption: true,
        coverMediaUrl: true,
        publishedAt: true,
      },
    });

    const data: ProfilePostItem[] = posts.map((post) => ({
      id: post.id,
      tripId: post.tripId,
      summaryText: post.summaryText,
      caption: post.caption ?? undefined,
      coverMediaUrl: post.coverMediaUrl ?? undefined,
      publishedAt: post.publishedAt?.toISOString(),
    }));

    return NextResponse.json<ApiResponse<ProfilePostItem[]>>({
      success: true,
      data,
    });
  } catch (error) {
    console.error("Get profile posts error:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}
