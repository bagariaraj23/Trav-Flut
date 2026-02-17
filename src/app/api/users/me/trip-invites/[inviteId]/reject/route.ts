import { NextRequest, NextResponse } from "next/server";
import { TripInvitationService } from "@/lib/tripInvitation";
import { ApiResponse } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Reject trip invitation
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ inviteId: string }> }
) {
  const { inviteId } = await params;
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const receiverId = authenticatedReq.user!.userId;

          await TripInvitationService.respondToInvitation(
            inviteId,
            receiverId,
            "reject"
          );

          return NextResponse.json<ApiResponse>({
            success: true,
            message: "Trip invitation rejected successfully",
          });
        } catch (error: any) {
          console.error("Reject trip invitation error:", error);

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
  });
  
  return await loggedHandler(request);
}
