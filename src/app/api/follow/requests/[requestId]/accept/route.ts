import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse, FollowResponse } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Accept a follow request
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ requestId: string }> }
) {
  const { requestId } = await params;
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;

          // Find the follow request
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

          // Verify that current user is the target of the request
          if (followRequest.followeeId !== currentUserId) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Unauthorized to accept this request",
              },
              { status: 403 }
            );
          }

          // Check if request is still pending
          if (followRequest.status !== "PENDING") {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Follow request is no longer pending",
              },
              { status: 400 }
            );
          }

          // Use transaction to handle race conditions
          const result = await prisma.$transaction(async (tx) => {
            // Check if follow relationship already exists (race condition protection)
            const existingFollow = await tx.follow.findUnique({
              where: {
                followerId_followeeId: {
                  followerId: followRequest.followerId,
                  followeeId: followRequest.followeeId,
                },
              },
            });

            let follow;
            if (existingFollow) {
              follow = existingFollow;
            } else {
              follow = await tx.follow.create({
                data: {
                  followerId: followRequest.followerId,
                  followeeId: followRequest.followeeId,
                },
              });
            }

            const updatedRequest = await tx.followRequest.update({
              where: { id: requestId },
              data: {
                status: "ACCEPTED",
                updatedAt: new Date(),
              },
            });

            return { follow, updatedRequest };
          });

          const followResponse: FollowResponse = {
            id: result.follow.id,
            followerId: result.follow.followerId,
            followeeId: result.follow.followeeId,
            createdAt: result.follow.createdAt.toISOString(),
          };

          return NextResponse.json<ApiResponse<FollowResponse>>(
            {
              success: true,
              data: followResponse,
              message: "Follow request accepted successfully",
            },
            { status: 201 }
          );
        } catch (error: any) {
          console.error("Accept follow request error:", error);

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
