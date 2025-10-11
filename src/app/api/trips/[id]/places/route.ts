import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { attachPlaceToTrip, getTripPlaces } from "@/lib/place";
import { AuthService } from "@/lib/auth";
import { ApiResponse } from "@/types/api";

async function assertTripAccess(tripId: string, userId: string) {
  const trip = await prisma.trip.findUnique({
    where: { id: tripId },
    include: { participants: true },
  });
  if (!trip) return { ok: false, code: 404 as const };
  const isOwner = trip.userId === userId;
  const isParticipant = trip.participants.some((p) => p.userId === userId);
  if (!isOwner && !isParticipant) return { ok: false, code: 403 as const };
  return { ok: true as const };
}

export async function GET(
  _req: NextRequest,
  { params }: { params: { id: string } }
) {
  const items = await getTripPlaces(params.id);
  return NextResponse.json<ApiResponse>({ success: true, data: items });
}

export async function POST(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
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

  const tripId = params.id;
  const access = await assertTripAccess(tripId, payload.userId);
  if (!access.ok)
    return NextResponse.json<ApiResponse>(
      {
        success: false,
        error: access.code === 404 ? "Trip not found" : "Forbidden",
      },
      { status: access.code }
    );

  const body = await request.json();
  const { placeId, visitedAt, dayIndex, notes, createThreadEntry } = body ?? {};
  if (!placeId)
    return NextResponse.json<ApiResponse>(
      { success: false, error: "placeId required" },
      { status: 400 }
    );

  const result = await attachPlaceToTrip(tripId, placeId, {
    visitedAt: visitedAt ? new Date(visitedAt) : undefined,
    dayIndex,
    notes,
    createThreadEntry: !!createThreadEntry,
    authorId: payload.userId,
  });

  return NextResponse.json<ApiResponse>(
    { success: true, data: result },
    { status: 201 }
  );
}
