import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";
import { ApiResponse, UserProfile } from "@/types/api";
import { CloudinaryService } from "@/lib/cloudinary";
import { updateProfileSchema } from "@/lib/validation";
import { handlePrismaUniqueError } from "@/lib/prismaErrors";

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
              oauthAccounts: { select: { id: true, provider: true } },
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

          const hasGoogleLinked = user.oauthAccounts.some(
            (a) => a.provider === "GOOGLE"
          );

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
            hasGoogleLinked,
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
          
          // Validate all profile data using schema (handles name, username, bio, avatarUrl, isPrivate)
          let validatedData;
          try {
            validatedData = updateProfileSchema.parse(body);
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
            throw error;
          }
          
          // Additional validation: name is mandatory when provided in body
          if ("name" in body && (!validatedData.name || validatedData.name.length < 1)) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Name is required" },
              { status: 400 }
            );
          }
          
          const { name, username, bio, avatarUrl, isPrivate } = validatedData;
          // When updating profile details (name, username, or bio), username is required
          const hasProfileDetailUpdate =
            "name" in body || "username" in body || "bio" in body;
          
          // Use transaction to prevent race condition and ensure username requirement check is atomic
          let updatedUser;
          try {
            updatedUser = await prisma.$transaction(async (tx) => {
              // Check username requirement inside transaction to prevent race condition
              if (hasProfileDetailUpdate) {
                const currentUser = await tx.user.findUnique({
                  where: { id: currentUserId },
                  select: { username: true },
                });
                const effectiveUsername =
                  username !== undefined ? username : currentUser?.username ?? null;
                if (!effectiveUsername?.trim()) {
                  throw new Error("Username is required to update profile details.");
                }
              }
              
              // Perform update inside transaction
              return await tx.user.update({
                where: { id: currentUserId },
                data: {
                  ...(name !== undefined && { name }),
                  ...(username !== undefined && { username }),
                  // bio is normalized above (empty string => null) so we can clear it
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
            });
          } catch (error: any) {
            // Handle username requirement error
            if (error.message === "Username is required to update profile details.") {
              return NextResponse.json<ApiResponse>(
                {
                  success: false,
                  error: error.message,
                },
                { status: 400 }
              );
            }
            
            // Handle unique constraint violations
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

            // Soft delete the user record; free email so same email can get a new account (start from zero)
            const deletedEmail = `deleted_${currentUserId}_${Date.now()}@deleted.local`;
            await tx.user.update({
              where: { id: currentUserId },
              data: {
                email: deletedEmail,
                deletedAt: new Date(),
                deleteMeta: {
                  deletedAt: new Date().toISOString(),
                  reason: "User initiated account deletion",
                },
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
