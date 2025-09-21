import { NextRequest, NextResponse } from "next/server";
import { TripInvitationService } from "@/lib/tripInvitation";
import { ApiResponse } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Accept trip invitation
export async function PUT(
  request: NextRequest,
  { params }: { params: { inviteId: string } }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const inviteId = params.inviteId;
          const receiverId = authenticatedReq.user!.userId;

          await TripInvitationService.respondToInvitation(
            inviteId,
            receiverId,
            "accept"
          );

          return NextResponse.json<ApiResponse>({
            success: true,
            message: "Trip invitation accepted successfully",
          });
        } catch (error: any) {
          console.error("Accept trip invitation error:", error);

          if (error.statusCode) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: error.message,
              },
              { status: error.statusCode }
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
      });
    });
  })(request);
}
