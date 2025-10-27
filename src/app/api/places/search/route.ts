import { NextRequest, NextResponse } from "next/server";
import { searchPlaces, resolvePlace } from "@/lib/place";
import { ApiResponse } from "@/types/api";
import { Place } from "@prisma/client";
import { debug } from "console";

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

    const ip = request.headers.get("x-forwarded-for") ?? request.ip ?? undefined;

    // 1. Search with caching
    console.log(`[Search] Query: "${q}" from IP: ${ip}`);
    const normalizedResults = await searchPlaces({
      q,
      lat: lat ? parseFloat(lat) : undefined,
      lng: lng ? parseFloat(lng) : undefined,
      limit: limit ? parseInt(limit, 10) : 10,
      ip,
    });

    if (normalizedResults.length === 0) {
      console.log("[Search] No results found");
      return NextResponse.json<ApiResponse>({ success: true, data: [] });
    }

    // 2. Resolve places in parallel with optimized caching
    console.log(`[Search] Resolving ${normalizedResults.length} places`);
    const resolvedPlacesPromises = normalizedResults.map(async (result) => {
      try {
        const resolved = await resolvePlace({
          name: result.name,
          address: result.address,
          lat: result.lat,
          lng: result.lng,
          externalId: result.externalId,
          placeType: result.placeType,
          source: result.source ?? "MAPBOX",
        });
        return resolved.place;
      } catch (error) {
        console.error(`[Search] Error resolving "${result.name}":`, error);
        return null;
      }
    });

    const resolvedPlaces = (await Promise.all(resolvedPlacesPromises)).filter(
      (place): place is Place => place !== null
    );

    console.log("[DEBUG] /api/places/search - Returning resolved places:", JSON.stringify(resolvedPlaces, null, 2));
    return NextResponse.json<ApiResponse<Place[]>>({
      success: true,
      data: resolvedPlaces,
    });
  } catch (error) {
    console.error("[Search] Unexpected error:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}