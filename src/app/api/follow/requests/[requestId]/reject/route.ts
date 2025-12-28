import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Reject a follow request
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
                error: "Unauthorized to reject this request",
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

          await prisma.followRequest.update({
            where: { id: requestId },
            data: {
              status: "REJECTED",
              updatedAt: new Date(),
            },
          });

          return NextResponse.json<ApiResponse>({
            success: true,
            message: "Follow request rejected successfully",
          });
        } catch (error: any) {
          console.error("Reject follow request error:", error);

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
