import { NextRequest, NextResponse } from "next/server";
import { resolvePlace } from "@/lib/place";
import { ApiResponse } from "@/types/api";
import { AuthService } from "@/lib/auth";
import { sanitizeInput } from "@/lib/security";
import { withAuth, withRateLimit, withLogging, handleApiError } from "@/lib/middleware";

export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    // Extract userId for rate limiting before auth
    let userId: string | undefined;
    const authHeader = req.headers.get("authorization");
    if (authHeader?.startsWith("Bearer ")) {
      try {
        const token = authHeader.substring(7);
        const payload = AuthService.verifyAccessToken(token);
        userId = payload?.userId;
      } catch {
        // Token invalid, will be caught by withAuth
      }
    }

    return withRateLimit(req, 'places', async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          // Validate and sanitize input
          const body = await rateLimitedReq.json();
          const { name, address, lat, lng, externalId, placeType, source } =
            body ?? {};

          if (!name || typeof lat !== "number" || typeof lng !== "number") {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Invalid input" },
              { status: 400 }
            );
          }

          // Sanitize text inputs
          const sanitizedName = sanitizeInput(name);
          const sanitizedAddress = address ? sanitizeInput(address) : undefined;

          // Validate coordinate bounds
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
            source,
          });

          return NextResponse.json<ApiResponse>(
            { success: true, data: out },
            { status: 201 }
          );
        } catch (error) {
          return handleApiError(error);
        }
      });
    }, { userId });
  })(request);
}
