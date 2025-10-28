import { NextRequest, NextResponse } from "next/server";
import { resolvePlace } from "@/lib/place";
import { ApiResponse } from "@/types/api";
import { getAuthSession } from "@/lib/auth";
import { enforceRateLimit, sanitizeInput } from "@/lib/security";

export async function POST(request: NextRequest) {
  try {
    // 1. Require authentication
    const session = await getAuthSession();
    if (!session?.user) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Authentication required" },
        { status: 401 }
      );
    }

    // 2. Rate limiting
    const rateLimitResult = await enforceRateLimit(
      request,
      session.user.id,
      "places:resolve"
    );
    if (!rateLimitResult.allowed) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Rate limit exceeded" },
        { status: 429 }
      );
    }

    // 3. Validate and sanitize input
    const body = await request.json();
    const { name, address, lat, lng, externalId, placeType, source } = body ?? {};

    if (!name || typeof lat !== "number" || typeof lng !== "number") {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Invalid input" },
        { status: 400 }
      );
    }

    // 4. Sanitize text inputs
    const sanitizedName = sanitizeInput(name);
    const sanitizedAddress = address ? sanitizeInput(address) : undefined;

    // 5. Validate coordinate bounds
    if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: "Invalid coordinates" },
        { status: 400 }
      );
    }

    const out = await resolvePlace({
      name: sanitizedName,
      address: sanitizedAddress,
      lat,
      lng,
      externalId,
      placeType,
      source
    });

    return NextResponse.json<ApiResponse>(
      { success: true, data: out },
      { status: 201 }
    );
  } catch (error) {
    console.error("[Resolve] Error:", error);
    return NextResponse.json<ApiResponse>(
      { success: false, error: "Internal server error" },
      { status: 500 }
    );
  }
}
