import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";
import { ApiResponse, UserProfile } from "@/types/api";

// Get current user profile
export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          console.log(`[API] GET /users/me - User: ${currentUserId}`);

          // Get current user with profile details
          const user = await prisma.user.findUnique({
            where: { id: currentUserId },
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
            console.error(
              `[API] GET /users/me - User not found: ${currentUserId}`
            );
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "User not found",
              },
              { status: 404 }
            );
          }

          console.log(
            `[API] GET /users/me - Found user: ${user.username || user.name}`
          );

          const userResponse: UserProfile = {
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
            data: userResponse,
          });
        } catch (error: any) {
          console.error(`[API] GET /users/me - Error:`, error);
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

// Update current user profile
export async function PUT(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          console.log(`[API] PUT /users/me - User: ${currentUserId}`);

          const body = await request.json();
          const { name, username, bio, avatarUrl, isPrivate } = body;

          console.log(`[API] PUT /users/me - Update data:`, {
            name,
            username,
            bio,
            avatarUrl,
            isPrivate,
          });

          // Validate input
          if (username && (username.length < 3 || username.length > 30)) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Username must be between 3 and 30 characters",
              },
              { status: 400 }
            );
          }

          if (name && (name.length < 1 || name.length > 100)) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Name must be between 1 and 100 characters",
              },
              { status: 400 }
            );
          }

          if (bio && bio.length > 500) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Bio must be less than 500 characters",
              },
              { status: 400 }
            );
          }

          // Check if username is already taken (if updating)
          if (username) {
            const existingUser = await prisma.user.findFirst({
              where: {
                username: username,
                id: { not: currentUserId },
              },
            });

            if (existingUser) {
              return NextResponse.json<ApiResponse>(
                {
                  success: false,
                  error: "Username is already taken",
                },
                { status: 400 }
              );
            }
          }

          // Update user profile
          const updatedUser = await prisma.user.update({
            where: { id: currentUserId },
            data: {
              ...(name !== undefined && { name }),
              ...(username !== undefined && { username }),
              ...(bio !== undefined && { bio }),
              ...(avatarUrl !== undefined && { avatarUrl }),
              ...(isPrivate !== undefined && { isPrivate }),
            },
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

          console.log(`[API] PUT /users/me - User updated successfully`);

          const userResponse: UserProfile = {
            ...updatedUser,
            username: updatedUser.username ?? undefined,
            name: updatedUser.name ?? undefined,
            avatarUrl: updatedUser.avatarUrl ?? undefined,
            bio: updatedUser.bio ?? undefined,
            createdAt: updatedUser.createdAt.toISOString(),
            updatedAt: updatedUser.updatedAt.toISOString(),
          };

          return NextResponse.json<ApiResponse<UserProfile>>({
            success: true,
            data: userResponse,
          });
        } catch (error: any) {
          console.error(`[API] PUT /users/me - Error:`, error);
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

// Delete current user account (soft delete)
export async function DELETE(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          console.log(`[API] DELETE /users/me - User: ${currentUserId}`);

          // Soft delete the user account
          await prisma.user.update({
            where: { id: currentUserId },
            data: {
              deletedAt: new Date(),
              deleteMeta: {
                deletedAt: new Date().toISOString(),
                reason: "User initiated account deletion",
              },
              // Clear sensitive data
              email: `deleted_${currentUserId}_${Date.now()}@deleted.local`,
              username: null,
              password: null,
              avatarUrl: null,
              bio: null,
            },
          });

          console.log(
            `[API] DELETE /users/me - Account deleted successfully: ${currentUserId}`
          );

          return NextResponse.json<ApiResponse>({
            success: true,
            message: "Account deleted successfully",
          });
        } catch (error: any) {
          console.error(`[API] DELETE /users/me - Error:`, error);
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
