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
});

async function updatePost(
  request: AuthenticatedRequest,
  postId: string
) {
  try {
    const body = bodySchema.parse(await request.json());
    const post = await UserPostService.update(
      postId,
      request.user!.userId,
      body
    );
    return NextResponse.json<ApiResponse>({ success: true, data: post });
  } catch (error) {
    if (error instanceof z.ZodError) {
      return NextResponse.json<ApiResponse>(
        { success: false, error: error.errors[0]?.message || "Invalid post" },
        { status: 400 }
      );
    }
    return handleApiError(error, { endpoint: "PATCH /user-posts/:id" });
  }
}

async function deletePost(request: AuthenticatedRequest, postId: string) {
  try {
    await UserPostService.remove(postId, request.user!.userId);
    return NextResponse.json<ApiResponse>({ success: true });
  } catch (error) {
    return handleApiError(error, { endpoint: "DELETE /user-posts/:id" });
  }
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  return withLogging(async (req) => {
    return withRateLimit(req, "media_upload", async (limited) => {
      return withAuth(limited, (authed) => updatePost(authed, id));
    });
  })(request);
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params;
  return withLogging(async (req) => {
    return withRateLimit(req, async (limited) => {
      return withAuth(limited, (authed) => deletePost(authed, id));
    });
  })(request);
}
