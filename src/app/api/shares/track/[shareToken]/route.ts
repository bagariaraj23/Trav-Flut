import { NextRequest, NextResponse } from "next/server";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { trackShareOpen } from "@/lib/services/share";
import { ApiResponse } from "@/types/api";
import { z } from "zod";

const trackShareSchema = z.object({
  platform: z.string().optional(),
  location: z.string().optional(),
  userAgent: z.string().optional(),
});

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ shareToken: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      try {
        const { shareToken } = await params;
        const body = await rateLimitedReq.json().catch(() => ({}));
        const validatedData = trackShareSchema.parse(body);
        const ipAddress =
          request.headers.get("x-forwarded-for") ||
          request.headers.get("x-real-ip") ||
          null;

        const metadata = {
          ...validatedData,
          ipAddress,
          timestamp: new Date().toISOString(),
        };

        await trackShareOpen(shareToken, metadata);

        return NextResponse.json<ApiResponse>({
          success: true,
          data: null,
        });
      } catch (error: any) {
        if (error.name === "ZodError") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: error.errors[0]?.message || "Validation error",
            },
            { status: 400 }
          );
        }
        if (error.message === "Share token not found") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Share token not found",
            },
            { status: 404 }
          );
        }
        return handleApiError(error);
      }
    });
  });

  return await loggedHandler(request);
}
