import { NextRequest, NextResponse } from "next/server";
import { z } from "zod";
import {
  withAuth,
  withLogging,
  withRateLimit,
  handleApiError,
  AuthenticatedRequest,
} from "@/lib/middleware";
import { UserPostService } from "@/lib/services/userPost";
import { ApiResponse } from "@/types/api";

const bodySchema = z.object({
  caption: z.string().min(1).max(2000),
  media: z.array(z.string().url()).max(12).optional(),
  locationName: z.string().max(200).nullable().optional(),
  latitude: z.number().nullable().optional(),
  longitude: z.number().nullable().optional(),
  placeId: z.string().uuid().nullable().optional(),
  isPublished: z.boolean().optional(),
});

async function createPost(request: AuthenticatedRequest) {
  try {
    const body = bodySchema.parse(await request.json());
    const post = await UserPostService.create(request.user!.userId, body);
    return NextResponse.json<ApiResponse>({ success: true, data: post });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: error.errors[0]?.message || "Invalid post" },
        { status: 400 }
      );
    }
    return handleApiError(error, { endpoint: "POST /user-posts" });
  }
}

export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, "media_upload", async (limited) => {
      return withAuth(limited, createPost);
    });
  })(request);
}
