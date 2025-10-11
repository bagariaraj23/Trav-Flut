import { NextRequest, NextResponse } from "next/server";
import { resolvePlace } from "@/lib/place";
import { ApiResponse } from "@/types/api";

export async function POST(request: NextRequest) {
  try {
    const body = await request.json();
    const { name, address, lat, lng, externalId, placeType, source } =
      body ?? {};
    if (!name || typeof lat !== "number" || typeof lng !== "number") {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Invalid input" },
        { status: 400 }
      );
    }
    const out = await resolvePlace({
      name,
      address,
      lat,
      lng,
      externalId,
      placeType,
      source,
    });
    return NextResponse.json<ApiResponse>(
      { success: true, data: out },
      { status: 201 }
    );
  } catch (e) {
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Bad request" },
      { status: 400 }
    );
  }
}
