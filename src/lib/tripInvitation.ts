import { prisma } from "./prisma";
import {
  AppError,
  NotFoundError,
  ConflictError,
  AuthorizationError,
} from "./errors";
import { TripJoinRequestStatus } from "@prisma/client";
import { handlePrismaUniqueError } from "./prismaErrors";

export class TripInvitationService {
  // Send a trip invitation
  static async sendInvitation(
    tripId: string,
    senderId: string,
    receiverId: string
  ) {
    try {
      return await prisma.$transaction(async (tx) => {
        // 1. Validate trip ownership
        const trip = await tx.trip.findUnique({ where: { id: tripId } });
        if (!trip) {
          throw new NotFoundError("Trip not found");
        }
        if (trip.userId !== senderId) {
          throw new AuthorizationError(
            "Only the trip owner can send invitations"
          );
        }

        // 2. Validate receiver exists
        const receiver = await tx.user.findUnique({
          where: { id: receiverId },
        });
        if (!receiver) {
          throw new NotFoundError("Invited user not found");
        }

        // 3. Prevent self-invitation
        if (senderId === receiverId) {
          throw new ConflictError("Cannot invite yourself to a trip");
        }

        // 4. Check if receiver is already a participant
        const existingParticipant = await tx.tripParticipant.findUnique({
          where: { tripId_userId: { tripId, userId: receiverId } },
        });
        if (existingParticipant) {
          throw new ConflictError("User is already a participant of this trip");
        }

        // 5. Check for existing pending invitation
        const existingRequest = await tx.tripJoinRequest.findUnique({
          where: { tripId_receiverId: { tripId, receiverId } },
        });
        if (
          existingRequest &&
          existingRequest.status === TripJoinRequestStatus.PENDING
        ) {
          return {
            id: existingRequest.id,
            status: existingRequest.status,
            message: "Invitation already pending",
          };
        }
        // If an old request exists (rejected/accepted), delete it before creating a new one
        if (existingRequest) {
          await tx.tripJoinRequest.delete({
            where: { id: existingRequest.id },
          });
        }

        // 6. Create new invitation
        const newRequest = await tx.tripJoinRequest.create({
          data: {
            tripId,
            senderId,
            receiverId,
            status: TripJoinRequestStatus.PENDING,
          },
        });

        return {
          id: newRequest.id,
          status: newRequest.status,
          message: "Invitation sent successfully",
        };
      });
    } catch (error: any) {
      // Use centralized error handler for unique constraint violations
      const uniqueError = handlePrismaUniqueError(error, {
        tripId_receiverId: "Trip invitation",
      });

      // If a concurrent create hits the DB unique constraint, map to existing request
      if (uniqueError) {
        // Try to fetch existing request for more context
        const existing = await prisma.tripJoinRequest.findUnique({
          where: { tripId_receiverId: { tripId, receiverId } },
        });
        if (existing) {
          return {
            id: existing.id,
            status: existing.status,
            message:
              existing.status === TripJoinRequestStatus.PENDING
                ? uniqueError || "Invitation already pending"
                : uniqueError || `Existing invitation with status ${existing.status}`,
          };
        }
        return {
          id: null,
          status: TripJoinRequestStatus.PENDING,
          message: uniqueError || "Invitation already exists",
        };
      }
      throw error;
    }
  }

  // Get pending invitations for a user
  static async getPendingInvitations(userId: string) {
    console.log(
      `[TripInvitationService] Getting pending invitations for user: ${userId}`
    );
    const invitations = await prisma.tripJoinRequest.findMany({
      where: {
        receiverId: userId,
        status: TripJoinRequestStatus.PENDING,
      },
      include: {
        trip: {
          select: {
            id: true,
            title: true,
            coverMediaId: true,
            userId: true,
            destinations: true,
            status: true,
            startDate: true,
            endDate: true,
          },
        },
        sender: {
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
        },
      },
      orderBy: { createdAt: "desc" },
    });

    console.log(
      `[TripInvitationService] Found ${invitations.length} pending invitations for user: ${userId}`
    );
    return invitations;
  }

  // Respond to an invitation (accept/reject)
  static async respondToInvitation(
    inviteId: string,
    receiverId: string,
    action: "accept" | "reject"
  ) {
    const request = await prisma.tripJoinRequest.findUnique({
      where: { id: inviteId },
    });

    if (!request) {
      throw new NotFoundError("Invitation not found");
    }
    if (request.receiverId !== receiverId) {
      throw new AuthorizationError(
        "Unauthorized to respond to this invitation"
      );
    }
    if (request.status !== TripJoinRequestStatus.PENDING) {
      throw new ConflictError("Invitation is no longer pending");
    }

    if (action === "accept") {
      return prisma.$transaction(async (tx) => {
        // Update invitation status
        const updatedRequest = await tx.tripJoinRequest.update({
          where: { id: inviteId },
          data: { status: TripJoinRequestStatus.ACCEPTED },
        });

        // Create participant entry
        await tx.tripParticipant.create({
          data: {
            tripId: request.tripId,
            userId: request.receiverId,
            role: "member",
          },
        });

        // Increment trip participant count
        await tx.trip.update({
          where: { id: request.tripId },
          data: { participantCount: { increment: 1 } },
        });

        return updatedRequest;
      });
    } else {
      return prisma.tripJoinRequest.update({
        where: { id: inviteId },
        data: { status: TripJoinRequestStatus.REJECTED },
      });
    }
  }

  // Get sent invitations for a trip (for trip owner to see pending invites)
  static async getSentInvitations(tripId: string, senderId: string) {
    // Verify trip ownership
    const trip = await prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) {
      throw new NotFoundError("Trip not found");
    }
    if (trip.userId !== senderId) {
      throw new AuthorizationError(
        "Only the trip owner can view sent invitations"
      );
    }

    return prisma.tripJoinRequest.findMany({
      where: {
        tripId,
        senderId,
        status: TripJoinRequestStatus.PENDING,
      },
      include: {
        receiver: {
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
        },
      },
      orderBy: { createdAt: "desc" },
    });
  }

  // Cancel a sent invitation (for trip owner)
  static async cancelInvitation(
    inviteId: string,
    tripId: string,
    senderId: string
  ) {
    // 1. Verify trip ownership
    const trip = await prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) {
      throw new NotFoundError("Trip not found");
    }
    if (trip.userId !== senderId) {
      throw new AuthorizationError(
        "Only the trip owner can cancel invitations"
      );
    }

    // 2. Find the invitation
    const request = await prisma.tripJoinRequest.findUnique({
      where: { id: inviteId },
    });

    if (!request) {
      throw new NotFoundError("Invitation not found");
    }

    // 3. Verify the invitation belongs to this trip and sender
    if (request.tripId !== tripId || request.senderId !== senderId) {
      throw new AuthorizationError("Unauthorized to cancel this invitation");
    }

    // 4. Only allow cancelling pending invitations
    if (request.status !== TripJoinRequestStatus.PENDING) {
      throw new ConflictError("Can only cancel pending invitations");
    }

    // 5. Delete the invitation
    console.log(
      `[TripInvitationService] Cancelling invitation ${inviteId} for trip ${tripId}`
    );
    await prisma.tripJoinRequest.delete({
      where: { id: inviteId },
    });

    console.log(
      `[TripInvitationService] Invitation ${inviteId} cancelled successfully`
    );
    return { message: "Invitation cancelled successfully" };
  }
}
