export const dynamic = "force-dynamic";

import { NextRequest, NextResponse } from "next/server";
import { searchPlaces, resolvePlace } from "@/lib/place";
import type { PlaceInput } from "@/lib/place";
import type { ApiResponse } from "@/types/api";
import { Place } from "@prisma/client";
import { getAuthSession } from "@/lib/auth";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";

export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    // Get authenticated user if available for rate limiting
    const session = await getAuthSession();
    const userId = session?.user?.id;

    return withRateLimit(req, 'places', async (rateLimitedReq) => {
      try {
        const { searchParams } = new URL(rateLimitedReq.url);
        const q = searchParams.get("q")?.trim() ?? "";
        const lat = searchParams.get("lat");
        const lng = searchParams.get("lng");
        const limit = searchParams.get("limit");

        // Early return for empty queries
        if (q.length < 2) {
          return NextResponse.json<ApiResponse>({ success: true, data: [] });
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
        return handleApiError(error);
      }
    }, { userId });
  })(request);
}