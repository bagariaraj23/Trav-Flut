import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";
import { ApiResponse, UserProfile } from "@/types/api";
import { CloudinaryService } from "@/lib/cloudinary";

// Get current user profile
export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          console.log(`[API] GET /users/me - User: ${currentUserId}`);

          // Get current user with profile details and oauthAccounts for profileComplete
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
              password: true,
              oauthAccounts: { select: { id: true } },
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

          const profileComplete =
            user.username != null &&
            (user.password != null || user.oauthAccounts.length === 0);

          const { password: _p, oauthAccounts: _oa, ...userFields } = user;
          const userResponse: UserProfile = {
            ...userFields,
            username: user.username ?? undefined,
            name: user.name ?? undefined,
            avatarUrl: user.avatarUrl ?? undefined,
            bio: user.bio ?? undefined,
            createdAt: user.createdAt.toISOString(),
            updatedAt: user.updatedAt.toISOString(),
            profileComplete,
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
  });
  
  return await loggedHandler(request);
}

// Update current user profile
export async function PUT(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          let body: Record<string, unknown>;
          try {
            body = (await request.json()) as Record<string, unknown>;
          } catch {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Invalid request body" },
              { status: 400 }
            );
          }
          if (body == null || typeof body !== "object" || Array.isArray(body)) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Invalid request body" },
              { status: 400 }
            );
          }
          let { name, username, bio, avatarUrl, isPrivate } = body as {
            name?: string | null;
            username?: string | null;
            bio?: string | null;
            avatarUrl?: string | null;
            isPrivate?: boolean | string | null;
          };
          // Normalize name: trim; treat empty/whitespace as null
          if (typeof name === "string") {
            const n = name.trim();
            name = n.length > 0 ? n : null;
          }
          // Normalize username: trim and treat empty/whitespace as null (clear)
          if (typeof username === "string") {
            const u = username.trim();
            username = u.length > 0 ? u : null;
          }
          // Normalize bio: trim and treat empty/whitespace as null (clear)
          if (typeof bio === "string") {
            const trimmed = bio.trim();
            bio = trimmed.length > 0 ? trimmed : null;
          }
          // Normalize avatarUrl: treat empty/whitespace as null
          if (typeof avatarUrl === "string") {
            const a = avatarUrl.trim();
            avatarUrl = a.length > 0 ? a : null;
          }
          // Normalize isPrivate: coerce string "true"/"false" to boolean; leave undefined if not a boolean
          if (typeof isPrivate === "string") {
            isPrivate = isPrivate === "true";
          }
          const isPrivateBool =
            typeof isPrivate === "boolean" ? isPrivate : undefined;
          // Validate input (name is mandatory when provided in body)
          if ("name" in body && (name == null || name.length < 1)) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Name is required" },
              { status: 400 }
            );
          }
          if (username != null && (username.length < 3 || username.length > 30)) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Username must be between 3 and 30 characters",
              },
              { status: 400 }
            );
          }
          if (name != null && (name.length < 1 || name.length > 100)) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Name must be between 1 and 100 characters",
              },
              { status: 400 }
            );
          }
          if (bio != null && bio.length > 200) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Bio must be 200 characters or less",
              },
              { status: 400 }
            );
          }
          // When updating profile details (name, username, or bio), username is required
          const hasProfileDetailUpdate =
            "name" in body || "username" in body || "bio" in body;
          if (hasProfileDetailUpdate) {
            const currentUser = await prisma.user.findUnique({
              where: { id: currentUserId },
              select: { username: true },
            });
            const effectiveUsername =
              username !== undefined ? username : currentUser?.username ?? null;
            if (!effectiveUsername?.trim()) {
              return NextResponse.json<ApiResponse>(
                {
                  success: false,
                  error:
                    "Username is required to update profile details.",
                },
                { status: 400 }
              );
            }
          }
          // Remove manual username uniqueness check; just try update
          let updatedUser;
          try {
            updatedUser = await prisma.user.update({
              where: { id: currentUserId },
              data: {
                ...(name !== undefined && { name }),
                ...(username !== undefined && { username }),
                // bio is normalized above (empty string => null) so we can clear it
                ...(bio !== undefined && { bio }),
                ...(avatarUrl !== undefined && { avatarUrl }),
                ...(isPrivateBool !== undefined && { isPrivate: isPrivateBool }),
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
          } catch (error: any) {
            const { handlePrismaUniqueError } = await import("@/lib/prismaErrors");
            const message = handlePrismaUniqueError(error, { username: "Username" });
            if (message) {
              return NextResponse.json<ApiResponse>(
                {
                  success: false,
                  error: message,
                },
                { status: 400 }
              );
            }
            throw error;
          }
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
  });
  return await loggedHandler(request);
}

// Delete current user account (soft delete)
export async function DELETE(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          console.log(`[API] DELETE /users/me - User: ${currentUserId}`);

          // Erase user and related personal data in a single transaction.
          // Collect media publicIds to optionally delete remote assets after the DB transaction.
          const mediaToDelete = await prisma.media.findMany({
            where: { uploadedById: currentUserId },
            select: { publicId: true },
          });

          await prisma.$transaction(async (tx) => {
            // Revoke tokens, sessions, and auth providers
            await tx.jWTRefreshToken.deleteMany({
              where: { userId: currentUserId },
            });
            await tx.oAuthAccount.deleteMany({
              where: { userId: currentUserId },
            });
            await tx.passwordReset.deleteMany({
              where: { userId: currentUserId },
            });
            await tx.securityEvent.deleteMany({
              where: { userId: currentUserId },
            });

            // Remove follow relations and requests
            await tx.follow.deleteMany({
              where: {
                OR: [
                  { followerId: currentUserId },
                  { followeeId: currentUserId },
                ],
              },
            });
            await tx.followRequest.deleteMany({
              where: {
                OR: [
                  { followerId: currentUserId },
                  { followeeId: currentUserId },
                ],
              },
            });

            // Remove trip-related links where user is directly referenced
            await tx.tripParticipant.deleteMany({
              where: { userId: currentUserId },
            });
            await tx.tripThreadTag.deleteMany({
              where: { taggedUserId: currentUserId },
            });
            await tx.tripJoinRequest.deleteMany({
              where: {
                OR: [
                  { senderId: currentUserId },
                  { receiverId: currentUserId },
                ],
              },
            });
            await tx.placeShare.deleteMany({
              where: { createdById: currentUserId },
            });

            // Delete thread entries and media uploaded by the user
            await tx.tripThreadEntry.deleteMany({
              where: { authorId: currentUserId },
            });
            await tx.media.deleteMany({
              where: { uploadedById: currentUserId },
            });

            // Soft delete the user record itself
            await tx.user.update({
              where: { id: currentUserId },
              data: {
                deletedAt: new Date(),
                deleteMeta: {
                  deletedAt: new Date().toISOString(),
                  reason: "User initiated account deletion",
                },
                email: `deleted_${currentUserId}_${Date.now()}@deleted.local`,
                username: null,
                password: null,
                avatarUrl: null,
                bio: null,
              },
            });

            console.log(
              `[API] DELETE /users/me - User record soft deleted: ${currentUserId}`
            );
          });

          // Optionally attempt to remove remote Cloudinary assets (best-effort).
          // Deleting remote assets is not part of the DB transaction (external IO).
          const deleteRemote = process.env.DELETE_REMOTE_MEDIA === "true";
          if (deleteRemote && mediaToDelete.length > 0) {
            (async () => {
              for (const m of mediaToDelete) {
                try {
                  await CloudinaryService.deleteMedia(m.publicId);
                  console.log(
                    `[API] DELETE /users/me - Deleted remote media ${m.publicId}`
                  );
                } catch (err) {
                  console.error(
                    `[API] DELETE /users/me - Failed to delete remote media ${m.publicId}:`,
                    err
                  );
                }
              }
            })();
          }

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
  });
  return await loggedHandler(request);
}
