import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { editMessage, deleteMessage } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";
import { z } from "zod";

const editBodySchema = z.object({
  content: z.string().min(1).max(512),
});

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; messageId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: conversationId, messageId } = await params;
        const userId = authReq.user!.userId;
        const body = await authReq.json();
        const parsed = editBodySchema.parse(body);

        const updated = await editMessage(conversationId, messageId, userId, parsed.content);

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

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; messageId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: conversationId, messageId } = await params;
        const userId = authReq.user!.userId;

        const deleted = await deleteMessage(conversationId, messageId, userId);

        return NextResponse.json<ApiResponse>(
          { success: true, data: deleted },
          { status: 200 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
