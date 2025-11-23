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
          console.log(`[API] POST /trips/${tripId}/invites - Sender: ${senderId}`);
          
          const body = await request.json();
          const { receiverId } = body;
          console.log(`[API] POST /trips/${tripId}/invites - Receiver: ${receiverId}`);

          if (!receiverId) {
            console.log(`[API] POST /trips/${tripId}/invites - Error: receiverId is required`);
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "receiverId is required",
              },
              { status: 400 }
            );
          }

          console.log(`[API] POST /trips/${tripId}/invites - Sending invitation from ${senderId} to ${receiverId}`);
          const result = await TripInvitationService.sendInvitation(
            tripId,
            senderId,
            receiverId
          );

          console.log(`[API] POST /trips/${tripId}/invites - Invitation sent successfully: ${result.id}, status: ${result.status}`);
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

          console.log(`[API] GET /trips/${tripId}/invites - Found ${sentInvitations.length} sent invitations`);
          
          const invitationsResponse = sentInvitations.map((invite: any) => {
            const receiver = invite.receiver;
            if (!receiver) {
              console.error(`[API] GET /trips/${tripId}/invites - Missing receiver for invitation ${invite.id}`);
              throw new Error(`Missing receiver for invitation ${invite.id}`);
            }
            
            if (!receiver.id || !receiver.email) {
              console.error(`[API] GET /trips/${tripId}/invites - Invalid receiver data:`, {
                id: receiver.id,
                email: receiver.email,
                invitationId: invite.id,
              });
              throw new Error(`Invalid receiver data for invitation ${invite.id}`);
            }

            // Ensure status is a valid string
            const status = invite.status || 'PENDING';
            
            const receiverData: any = {
              id: String(receiver.id),
              email: String(receiver.email),
              isPrivate: Boolean(receiver.isPrivate),
              createdAt: receiver.createdAt.toISOString(),
              updatedAt: receiver.updatedAt.toISOString(),
            };
            
            // Only include optional fields if they exist
            if (receiver.username) receiverData.username = String(receiver.username);
            if (receiver.name) receiverData.name = String(receiver.name);
            if (receiver.avatarUrl) receiverData.avatarUrl = String(receiver.avatarUrl);
            if (receiver.bio) receiverData.bio = String(receiver.bio);
            
            return {
              id: String(invite.id),
              tripId: String(invite.tripId),
              senderId: String(invite.senderId),
              receiverId: String(invite.receiverId),
              status: status,
              createdAt: invite.createdAt.toISOString(),
              updatedAt: invite.updatedAt.toISOString(),
              receiver: receiverData,
            };
          });

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

// Cancel a sent invitation
export async function DELETE(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const tripId = params.id;
          const senderId = authenticatedReq.user!.userId;
          
          const { searchParams } = new URL(request.url);
          const inviteId = searchParams.get("inviteId");
          
          console.log(`[API] DELETE /trips/${tripId}/invites - Sender: ${senderId}, InviteId: ${inviteId}`);

          if (!inviteId) {
            console.log(`[API] DELETE /trips/${tripId}/invites - Error: inviteId is required`);
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "inviteId is required",
              },
              { status: 400 }
            );
          }

          console.log(`[API] DELETE /trips/${tripId}/invites - Cancelling invitation ${inviteId}`);
          const result = await TripInvitationService.cancelInvitation(
            inviteId,
            tripId,
            senderId
          );

          console.log(`[API] DELETE /trips/${tripId}/invites - Invitation cancelled successfully`);
          return NextResponse.json<ApiResponse>({
            success: true,
            message: result.message,
          });
        } catch (error: any) {
          console.error("Cancel trip invitation error:", error);

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
