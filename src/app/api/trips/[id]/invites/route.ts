import { NextRequest, NextResponse } from "next/server";
import { TripInvitationService } from "@/lib/tripInvitation";
import { AuthService } from "@/lib/auth";
import { ApiResponse } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Send trip invitation
export async function POST(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const tripId = params.id;
          const senderId = authenticatedReq.user!.userId;
          const body = await request.json();
          const { receiverId } = body;

          if (!receiverId) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "receiverId is required",
              },
              { status: 400 }
            );
          }

          const result = await TripInvitationService.sendInvitation(
            tripId,
            senderId,
            receiverId
          );

          return NextResponse.json<ApiResponse>({
            success: true,
            data: { id: result.id, status: result.status },
            message: result.message,
          });
        } catch (error: any) {
          console.error("Send trip invitation error:", error);

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

// Get sent invitations for a trip (for trip owner)
export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const tripId = params.id;
          const senderId = authenticatedReq.user!.userId;

          const sentInvitations =
            await TripInvitationService.getSentInvitations(tripId, senderId);

          // Transform to response format
          const invitationsResponse = sentInvitations.map((invite: any) => ({
            id: invite.id,
            tripId: invite.tripId,
            senderId: invite.senderId,
            receiverId: invite.receiverId,
            status: invite.status,
            createdAt: invite.createdAt.toISOString(),
            updatedAt: invite.updatedAt.toISOString(),
            receiver: {
              ...invite.receiver,
              username: invite.receiver.username ?? undefined,
              name: invite.receiver.name ?? undefined,
              avatarUrl: invite.receiver.avatarUrl ?? undefined,
              bio: invite.receiver.bio ?? undefined,
              createdAt: invite.receiver.createdAt.toISOString(),
              updatedAt: invite.receiver.updatedAt.toISOString(),
            },
          }));

          return NextResponse.json<ApiResponse>({
            success: true,
            data: invitationsResponse,
          });
        } catch (error: any) {
          console.error("Get sent invitations error:", error);

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
