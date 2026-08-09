import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { getConversation, updateGroupDetails } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";
import { z } from "zod";

const updateGroupSchema = z.object({
  name: z.string().min(1).max(100).optional().nullable(),
  avatarUrl: z.string().url().optional().nullable(),
});

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const userId = authReq.user!.userId;
        const conversation = await getConversation(id, userId);
        return NextResponse.json<ApiResponse>(
          { success: true, data: conversation },
          { status: 200 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const userId = authReq.user!.userId;
        const body = await authReq.json();
        const parsed = updateGroupSchema.parse(body);

        const updated = await updateGroupDetails(id, userId, {
          name: parsed.name,
          avatarUrl: parsed.avatarUrl,
        });

        return NextResponse.json<ApiResponse>(
          { success: true, data: updated },
          { status: 200 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
