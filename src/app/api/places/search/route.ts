import { NextRequest, NextResponse } from "next/server";
import { searchPlaces } from "@/lib/place";
import { ApiResponse } from "@/types/api";

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
  const results = await searchPlaces({
    q,
    lat: lat ? parseFloat(lat) : undefined,
    lng: lng ? parseFloat(lng) : undefined,
    limit: limit ? parseInt(limit, 10) : 10,
    ip,
  });

  return NextResponse.json<ApiResponse>({ success: true, data: results });
}
