import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { updateProfileSchema } from "@/lib/validation";
import { ApiResponse, UserProfile, UserStats } from "@/types/api";

// Get user profile
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const userId = id;

    // Get current user from token (optional)
    const authHeader = request.headers.get("authorization");
    let currentUserId: string | null = null;

    if (authHeader?.startsWith("Bearer ")) {
      const token = authHeader.substring(7);
      const payload = AuthService.verifyAccessToken(token);
      currentUserId = payload?.userId || null;
    }

    // Find user
    const user = await prisma.user.findUnique({
      where: { id: userId },
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
    });

    if (!user) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "User not found",
        },
        { status: 404 }
      );
    }

    // Check privacy settings
    if (user.isPrivate && currentUserId !== userId) {
      // Check if current user follows this user
      if (currentUserId) {
        const followRelation = await prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: currentUserId,
              followeeId: userId,
            },
          },
        });

        if (!followRelation) {
          // Return limited profile for private users
          const limitedProfile: UserProfile = {
            id: user.id,
            email: "", // Hide email for privacy
            username: user.username,
            name: user.name,
            avatarUrl: user.avatarUrl,
            bio: undefined, // Hide bio for privacy
            isPrivate: user.isPrivate,
            createdAt: user.createdAt.toISOString(),
            updatedAt: user.updatedAt.toISOString(),
          };

          return NextResponse.json<
            ApiResponse<UserProfile & { message?: string }>
          >({
            success: true,
            data: {
              ...limitedProfile,
              message: "This profile is private. Follow to see more details.",
            },
          });
        }
      } else {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: "This profile is private",
          },
          { status: 403 }
        );
      }
    }

    const userProfile: UserProfile = {
      ...user,
      username: user.username ?? undefined,
      name: user.name ?? undefined,
      avatarUrl: user.avatarUrl ?? undefined,
      bio: user.bio ?? undefined,
      createdAt: user.createdAt.toISOString(),
      updatedAt: user.updatedAt.toISOString(),
    };

    return NextResponse.json<ApiResponse<UserProfile>>({
      success: true,
      data: userProfile,
    });
  } catch (error: any) {
    console.error("Get user error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}

// Update user profile
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const userId = id;
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
    if (!payload || payload.userId !== userId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Unauthorized",
        },
        { status: 403 }
      );
    }
    const body = await request.json();
    const validatedData = updateProfileSchema.parse(body);
    // Remove manual check; try update and catch P2002 unique error
    let updatedUser;
    try {
      updatedUser = await prisma.user.update({
        where: { id: userId },
        data: { ...validatedData, updatedAt: new Date() },
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
      });
    } catch (error: any) {
      if (error.code === "P2002" && error.meta?.target?.includes("username")) {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: "Username is already taken",
          },
          { status: 400 }
        );
      }
      throw error;
    }
    const userProfile: UserProfile = {
      ...updatedUser,
      createdAt: updatedUser.createdAt.toISOString(),
      updatedAt: updatedUser.updatedAt.toISOString(),
    };
    return NextResponse.json<ApiResponse<UserProfile>>({
      success: true,
      data: userProfile,
    });
  } catch (error: any) {
    if (error.name === "ZodError") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: error.errors[0]?.message || "Validation error",
        },
        { status: 400 }
      );
    }
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
