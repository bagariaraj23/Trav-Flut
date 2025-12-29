import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { AuthService } from "@/lib/auth";
import { ApiResponse } from "@/types/api";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; placeOnTripId: string }> }
) {
  const { id, placeOnTripId } = await params;
  const authHeader = request.headers.get("authorization");
  if (!authHeader?.startsWith("Bearer ")) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Unauthorized" },
      { status: 401 }
    );
  }
  const token = authHeader.substring(7);
  const payload = AuthService.verifyAccessToken(token);
  if (!payload)
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Invalid token" },
      { status: 401 }
    );

  const pot = await prisma.placeOnTrip.findUnique({
    where: { id: placeOnTripId },
  });
  if (!pot || pot.tripId !== id) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Not found" },
      { status: 404 }
    );
  }
  const trip = await prisma.trip.findUnique({
    where: { id: pot.tripId },
    include: { participants: true },
  });
  if (!trip)
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Trip not found" },
      { status: 404 }
    );
  const isOwner = trip.userId === payload.userId;
  const isParticipant = trip.participants.some(
    (p) => p.userId === payload.userId
  );
  if (!isOwner && !isParticipant)
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Forbidden" },
      { status: 403 }
    );

  await prisma.placeOnTrip.delete({ where: { id: pot.id } });
  return NextResponse.json<ApiResponse>({ success: true });
}
