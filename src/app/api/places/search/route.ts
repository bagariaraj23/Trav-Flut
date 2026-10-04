export const dynamic = "force-dynamic";

import { NextRequest, NextResponse } from "next/server";
import { searchPlaces, resolvePlace } from "@/lib/place";
import type { PlaceInput } from "@/lib/place";
import type { ApiResponse } from "@/types/api";
import { MapboxRequestError } from "@/lib/mapProviders/mapbox";
import { getAuthSession } from "@/lib/auth";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { validateSqlInput } from "@/lib/security";

export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
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

        // Validate SQL injection patterns in search query
        if (q && !validateSqlInput(q)) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Invalid search query",
            },
            { status: 400 }
          );
        }

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

    const uniqueInputs = new Map<string, PlaceInput>();
    for (const result of normalizedResults) {
      const placeInput: PlaceInput = {
        name: result.name,
        address: result.address ?? undefined,
        lat: result.lat,
        lng: result.lng,
        externalId: result.externalId ?? undefined,
        placeType: result.placeType ?? "POI",
        source: result.source ?? "MAPBOX",
      };
      const dedupeKey =
        placeInput.externalId ??
        `${placeInput.lat.toFixed(5)}:${placeInput.lng.toFixed(5)}:${placeInput.name.toLowerCase()}`;
      if (!uniqueInputs.has(dedupeKey)) {
        uniqueInputs.set(dedupeKey, placeInput);
      }
    }

    const resolvedPlaces = (
      await Promise.all(
        Array.from(uniqueInputs.values()).map(async (placeInput) => {
          try {
            const place = await resolvePlace(placeInput);
            if (!place) return null;
            return {
              id: place.id,
              name: place.name,
              address: place.address,
              lat: place.lat,
              lng: place.lng,
              placeType: place.placeType,
              source: place.source,
              externalId: place.externalId,
              createdAt: place.createdAt,
              updatedAt: place.updatedAt,
            };
          } catch (error) {
            console.error(`[Search] Error resolving "${placeInput.name}":`, error);
            return null;
          }
        })
      )
    ).filter((place): place is NonNullable<typeof place> => place !== null);

        return NextResponse.json<ApiResponse<typeof resolvedPlaces>>({
          success: true,
          data: resolvedPlaces,
        });
      } catch (error) {
        if (error instanceof MapboxRequestError) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Place search is temporarily unavailable" },
            { status: 502 }
          );
        }
        return handleApiError(error);
      }
    }, { userId });
  });
  
  return await loggedHandler(request);
}