import { NextRequest, NextResponse } from "next/server";
import { searchPlaces, resolvePlace } from "@/lib/place";
import { ApiResponse } from "@/types/api";
import { Place } from "@prisma/client";
import { debug } from "console";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const q = searchParams.get("q") ?? "";
  const lat = searchParams.get("lat");
  const lng = searchParams.get("lng");
  const limit = searchParams.get("limit");

  if (!q) {
    return NextResponse.json<ApiResponse>({ success: true, data: [] });
  }

  const ip = request.headers.get("x-forwarded-for") ?? request.ip ?? undefined;

  // 1. Get normalized results from Mapbox
  const normalizedResults = await searchPlaces({
    q,
    lat: lat ? parseFloat(lat) : undefined,
    lng: lng ? parseFloat(lng) : undefined,
    limit: limit ? parseInt(limit, 10) : 10,
    ip,
  });

  console.log("[DEBUG] /api/places/search - Normalized results:", JSON.stringify(normalizedResults, null, 2));

  // 2. Resolve each normalized result against your database
  // This finds existing places or creates new ones and returns your DB Place objects
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
      // resolvePlace returns { placeId: string, place: Place }
      return resolved.place; 
    } catch (error) {
      console.error(`Error resolving place "${result.name}":`, error);
      return null;
    }
  });

  const resolvedPlaces = (await Promise.all(resolvedPlacesPromises)).filter(
    (place): place is Place => place !== null
  );

  console.log("[DEBUG] /api/places/search - Returning resolved places:", JSON.stringify(resolvedPlaces, null, 2));

  // 3. Return the array of Place objects from your database
  return NextResponse.json<ApiResponse<Place[]>>({
    success: true,
    data: resolvedPlaces,
  });
}