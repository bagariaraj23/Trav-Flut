export const dynamic = "force-dynamic";

import { NextRequest, NextResponse } from "next/server";
import { searchPlaces, resolvePlace } from "@/lib/place";
import type { PlaceInput } from "@/lib/place";
import type { ApiResponse } from "@/types/api";
import { Place } from "@prisma/client";
import { getAuthSession } from "@/lib/auth";
import { enforceRateLimit } from "@/lib/security";

export async function GET(request: NextRequest) {
  try {
    const { searchParams } = new URL(request.url);
    const q = searchParams.get("q")?.trim() ?? "";
    const lat = searchParams.get("lat");
    const lng = searchParams.get("lng");
    const limit = searchParams.get("limit");

    // Early return for empty queries
    if (q.length < 2) {
      return NextResponse.json<ApiResponse>({ success: true, data: [] });
    }

    // Get authenticated user if available
    const session = await getAuthSession();
    const userId = session?.user?.id;

    // Enhanced rate limiting with security checks
    const rateLimitResult = await enforceRateLimit(request, userId, "places:search");
    if (!rateLimitResult.allowed) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: "Rate limit exceeded",
          meta: {
            resetAt: new Date(rateLimitResult.resetAt * 1000).toISOString(),
            retryAfter: rateLimitResult.resetAt - Math.floor(Date.now() / 1000)
          }
        },
        {
          status: 429,
          headers: {
            'Retry-After': String(rateLimitResult.resetAt - Math.floor(Date.now() / 1000))
          }
        }
      );
    }

    const normalizedResults = await searchPlaces({
      q,
      lat: lat ? parseFloat(lat) : undefined,
      lng: lng ? parseFloat(lng) : undefined,
      limit: limit ? parseInt(limit, 10) : 10,
      userId,
    });

    if (normalizedResults.length === 0) {
      return NextResponse.json<ApiResponse>({ success: true, data: [] });
    }

    const resolvedPlacesPromises = normalizedResults.map(async (result) => {
      try {
        // Ensure all fields match expected types
        const placeInput: PlaceInput = {
          name: result.name,
          address: result.address ?? undefined,
          lat: result.lat,
          lng: result.lng,
          externalId: result.externalId ?? undefined,
          placeType: result.placeType ?? 'POI',
          source: result.source ?? "MAPBOX",
        };

        const place = await resolvePlace(placeInput);
        if (!place) throw new Error('Place resolution failed');
        return place;
      } catch (error) {
        console.error(`[Search] Error resolving "${result.name}":`, error);
        return null;
      }
    });

    const resolvedPlaces = (await Promise.all(resolvedPlacesPromises)).filter(
      (place): place is Place => place !== null
    );

    return NextResponse.json<ApiResponse<Place[]>>({
      success: true,
      data: resolvedPlaces,
    });
  } catch (error) {
    console.error("[Search] Error:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}