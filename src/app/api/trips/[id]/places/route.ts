import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { attachPlaceToTrip, serializePlace } from "@/lib/place";
import { AuthService } from "@/lib/auth";
import { ApiResponse, MapPlaceResponse } from "@/types/api";

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
  req: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const tripId = params.id;

    // Optional: Check authentication for access control
    const authHeader = req.headers.get("authorization");
    let userId: string | undefined;
    if (authHeader?.startsWith("Bearer ")) {
      const token = authHeader.substring(7);
      const payload = AuthService.verifyAccessToken(token);
      userId = payload?.userId;
    }

    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      select: {
        startLocationId: true,
        endLocationId: true,
        startDate: true,
        endDate: true,
        userId: true,
        participants: {
          select: { userId: true },
        },
        placeVisits: {
          include: { place: true },
          orderBy: [{ visitedAt: "asc" }, { order: "asc" }],
        },
        threadEntries: {
          where: {
            type: { in: ["LOCATION", "CHECKIN"] },
            placeId: { not: null },
          },
          select: {
            id: true,
            placeId: true,
            contentText: true,
            createdAt: true,
            place: true,
          },
          orderBy: {
            createdAt: "asc",
          },
        },
      },
    });

    if (!trip) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Trip not found" },
        { status: 404 }
      );
    }

    // Check access if user is authenticated
    if (userId) {
      const isOwner = trip.userId === userId;
      const isParticipant = trip.participants.some((p) => p.userId === userId);
      if (!isOwner && !isParticipant) {
        return NextResponse.json<ApiResponse>(
          { success: false, error: "Forbidden" },
          { status: 403 }
        );
      }
    }

    // Destination places
    const destPlaceIds = [trip.startLocationId, trip.endLocationId].filter(
      Boolean
    ) as string[];

    const destinationPlaces = destPlaceIds.length
      ? await prisma.place.findMany({ where: { id: { in: destPlaceIds } } })
      : [];

    const destinationMapPlaces: MapPlaceResponse[] = destinationPlaces.map(
      (place, idx) => ({
        place: serializePlace(place),
        origin: "DESTINATION" as const,
        destinationIndex: idx as number,
        visitedAt:
          idx === 0
            ? trip.startDate?.toISOString()
            : trip.endDate?.toISOString(),
      })
    );

    // PlaceOnTrip records
    const onTripMapPlaces: MapPlaceResponse[] = trip.placeVisits.map((pot) => ({
      place: serializePlace(pot.place),
      origin: "ON_TRIP" as const,
      visitedAt: pot.visitedAt?.toISOString(),
      dayIndex: pot.dayIndex !== null ? (pot.dayIndex as number) : undefined,
      notes: pot.notes ?? undefined,
      order: pot.order !== null ? (pot.order as number) : undefined,
      placeOnTripId: pot.id,
    }));

    // Thread entry places
    const threadEntryMapPlaces: MapPlaceResponse[] = trip.threadEntries
      .map((entry) => {
        // Skip entries without place
        if (!entry.place) return null;

        return {
          place: serializePlace(entry.place),
          origin: "THREAD_ENTRY" as const,
          threadEntryId: entry.id,
          notes: entry.contentText,
          createdAt: entry.createdAt.toISOString(),
        } as MapPlaceResponse;
      })
      .filter((entry): entry is MapPlaceResponse => entry !== null);

    // Combine all places
    const allMapPlaces: MapPlaceResponse[] = [
      ...destinationMapPlaces,
      ...onTripMapPlaces,
      ...threadEntryMapPlaces,
    ];

    // Sort chronologically
    allMapPlaces.sort((a, b) => {
      const timeA = new Date(a.visitedAt || a.createdAt || 0).getTime();
      const timeB = new Date(b.visitedAt || b.createdAt || 0).getTime();
      return timeA - timeB;
    });

    // Return properly typed response
    return NextResponse.json<ApiResponse<MapPlaceResponse[]>>({
      success: true,
      data: allMapPlaces,
    });
  } catch (error) {
    console.error("[GET /api/trips/[id]/places] Error:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
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
