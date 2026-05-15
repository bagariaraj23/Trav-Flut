import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { addParticipantSchema } from "@/lib/validation";
import { ApiResponse, TripParticipantResponse } from "@/types/api";

// Add participant to trip
export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const tripId = id;

    // Verify authentication
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Authorization token required",
        },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);

    if (!payload) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid token",
        },
        { status: 401 }
      );
    }

    const currentUserId = payload.userId;
    const body = await request.json();

    // Validate input
    const validatedData = addParticipantSchema.parse(body);

    // Check if trip exists and user is owner
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
    });

    if (!trip) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Trip not found",
        },
        { status: 404 }
      );
    }

    if (trip.userId !== currentUserId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Only trip owner can add participants",
        },
        { status: 403 }
      );
    }

    const ownerProfile = await prisma.user.findUnique({
      where: { id: trip.userId },
      select: { isPrivate: true },
    });
    if (ownerProfile?.isPrivate) {
      const follow = await prisma.follow.findUnique({
        where: {
          followerId_followeeId: {
            followerId: validatedData.userId,
            followeeId: trip.userId,
          },
        },
      });
      if (!follow) {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error:
              "User must follow the private trip owner before they can be added as a participant.",
          },
          { status: 403 }
        );
      }
    }

    // Check if user to be added exists
    const userToAdd = await prisma.user.findUnique({
      where: { id: validatedData.userId },
    });

    if (!userToAdd) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "User not found",
        },
        { status: 404 }
      );
    }

    // Check if user is already a participant
    const existingParticipant = await prisma.tripParticipant.findUnique({
      where: {
        tripId_userId: {
          tripId,
          userId: validatedData.userId,
        },
      },
    });

    if (existingParticipant) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "User is already a participant",
        },
        { status: 400 }
      );
    }

    // Add participant and increment participantCount in a transaction
    const [participant, _] = await prisma.$transaction([
      prisma.tripParticipant.create({
        data: {
          tripId,
          userId: validatedData.userId,
          role: validatedData.role || "member",
        },
        include: {
          user: {
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
      }),
      prisma.trip.update({
        where: { id: tripId },
        data: { participantCount: { increment: 1 }, updatedAt: new Date() },
      }),
    ]);

    const participantResponse: TripParticipantResponse = {
      ...participant,
      joinedAt: participant.joinedAt.toISOString(),
      user: {
        ...participant.user,
        username: participant.user.username || null,
        name: participant.user.name || null,
        avatarUrl: participant.user.avatarUrl || null,
        bio: participant.user.bio || null,
        createdAt: participant.user.createdAt.toISOString(),
        updatedAt: participant.user.updatedAt.toISOString(),
      },
    };

    return NextResponse.json<ApiResponse<TripParticipantResponse>>(
      {
        success: true,
        data: participantResponse,
      },
      { status: 201 }
    );
  } catch (error: any) {
    console.error("Add participant error:", error);

    if (error.name === "ZodError") {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: error.errors[0]?.message || "Validation error",
        },
        { status: 400 }
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
}

// DELETE handler to remove a participant
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const tripId = id;
    const url = new URL(request.url);
    const userIdToRemove = url.searchParams.get("userId");
    if (!userIdToRemove) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "userId query parameter is required",
        },
        { status: 400 }
      );
    }
    // Verify authentication
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Authorization token required",
        },
        { status: 401 }
      );
    }
    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);
    if (!payload) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid token",
        },
        { status: 401 }
      );
    }
    const currentUserId = payload.userId;
    // Check if trip exists and user is owner
    const trip = await prisma.trip.findUnique({ where: { id: tripId } });
    if (!trip) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Trip not found",
        },
        { status: 404 }
      );
    }
    if (trip.userId !== currentUserId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Only trip owner can remove participants",
        },
        { status: 403 }
      );
    }
    // Prevent owner from removing themselves
    if (userIdToRemove === currentUserId) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Owner cannot remove themselves from the trip",
        },
        { status: 400 }
      );
    }
    // Remove participant, delete any pending TripJoinRequest, and decrement participantCount in a transaction
    await prisma.$transaction([
      prisma.tripParticipant.delete({
        where: {
          tripId_userId: {
            tripId,
            userId: userIdToRemove,
          },
        },
      }),
      prisma.trip.update({
        where: { id: tripId },
        data: { participantCount: { decrement: 1 }, updatedAt: new Date() },
      }),
      prisma.tripJoinRequest.deleteMany({
        where: {
          tripId,
          receiverId: userIdToRemove,
          status: "PENDING",
        },
      }),
    ]);
    return NextResponse.json<ApiResponse>({
      success: true,
      message: "Participant and any pending join requests removed successfully",
    });
  } catch (error: any) {
    console.error("Remove participant error:", error);
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}

// Get trip participants
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const tripId = id;

    // Verify authentication
    const authHeader = request.headers.get("authorization");
    if (!authHeader?.startsWith("Bearer ")) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Authorization token required",
        },
        { status: 401 }
      );
    }

    const token = authHeader.substring(7);
    const payload = AuthService.verifyAccessToken(token);

    if (!payload) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Invalid token",
        },
        { status: 401 }
      );
    }

    const userId = payload.userId;

    // Check if trip exists and user has access
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        participants: true,
        user: {
          select: { isPrivate: true },
        },
      },
    });

    if (!trip) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Trip not found",
        },
        { status: 404 }
      );
    }

    // Check access permissions
    const isOwner = trip.userId === userId;
    const isParticipant = trip.participants.some((p) => p.userId === userId);

    if (!isOwner && !isParticipant) {
      // Check if trip owner's profile is public or if current user follows them
      if (trip.user?.isPrivate) {
        const followRelation = await prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: userId,
              followeeId: trip.userId,
            },
          },
        });

        if (!followRelation) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Access denied to this private trip",
            },
            { status: 403 }
          );
        }
      }
    }

    // Get participants
    const participants = await prisma.tripParticipant.findMany({
      where: { tripId },
      include: {
        user: {
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
      orderBy: { joinedAt: "asc" },
    });

    const participantsResponse: TripParticipantResponse[] = participants.map(
      (participant) => ({
        ...participant,
        joinedAt: participant.joinedAt.toISOString(),
        user: {
          ...participant.user,
          username: participant.user.username || null,
          name: participant.user.name || null,
          avatarUrl: participant.user.avatarUrl || null,
          bio: participant.user.bio || null,
          createdAt: participant.user.createdAt.toISOString(),
          updatedAt: participant.user.updatedAt.toISOString(),
        },
      })
    );

    return NextResponse.json<ApiResponse<TripParticipantResponse[]>>({
      success: true,
      data: participantsResponse,
    });
  } catch (error: any) {
    console.error("Get participants error:", error);

    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: "Internal server error",
      },
      { status: 500 }
    );
  }
}
