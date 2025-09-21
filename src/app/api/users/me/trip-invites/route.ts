import { NextRequest, NextResponse } from "next/server";
import { TripInvitationService } from "@/lib/tripInvitation";
import { ApiResponse } from "@/types/api";
import { withAuth, withRateLimit, withLogging } from "@/lib/middleware";

// Get pending trip invitations for current user
export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const userId = authenticatedReq.user!.userId;

          const pendingInvitations =
            await TripInvitationService.getPendingInvitations(userId);

          // Transform to response format
          const invitationsResponse = pendingInvitations.map((invite: any) => ({
            id: invite.id,
            tripId: invite.tripId,
            senderId: invite.senderId,
            receiverId: invite.receiverId,
            status: invite.status,
            createdAt: invite.createdAt.toISOString(),
            updatedAt: invite.updatedAt.toISOString(),
            trip: invite.trip
              ? {
                  id: invite.trip.id,
                  title: invite.trip.title,
                  coverMediaUrl: invite.trip.coverMediaUrl ?? undefined,
                  userId: invite.trip.userId,
                  destinations: invite.trip.destinations,
                  status: invite.trip.status,
                  startDate: invite.trip.startDate?.toISOString() ?? undefined,
                  endDate: invite.trip.endDate?.toISOString() ?? undefined,
                }
              : undefined,
            sender: invite.sender
              ? {
                  ...invite.sender,
                  username: invite.sender.username ?? undefined,
                  name: invite.sender.name ?? undefined,
                  avatarUrl: invite.sender.avatarUrl ?? undefined,
                  bio: invite.sender.bio ?? undefined,
                  createdAt: invite.sender.createdAt.toISOString(),
                  updatedAt: invite.sender.updatedAt.toISOString(),
                }
              : undefined,
          }));

          return NextResponse.json<ApiResponse>({
            success: true,
            data: invitationsResponse,
          });
        } catch (error: any) {
          console.error("Get pending trip invitations error:", error);

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
