import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { deleteMessage, editMessage, getMessages, sendMessage } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";
import { z, ZodError } from "zod";

const sendBodySchema = z.object({
  content: z.string().max(512).optional(),
  replyToMessageId: z.string().uuid().optional().nullable(),
  attachmentMediaIds: z.array(z.string().uuid()).optional(),
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
        const { searchParams } = new URL(authReq.url);
        const limit = searchParams.get("limit");
        const before = searchParams.get("before") ?? undefined;
        const result = await getMessages(id, userId, {
          limit: limit ? parseInt(limit, 10) : undefined,
          before,
        });
        return NextResponse.json<ApiResponse>(
          { success: true, data: result },
          { status: 200 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const userId = authReq.user!.userId;
        const body = await authReq.json();
        const parsed = sendBodySchema.parse(body);
        const message = await sendMessage(id, userId, {
          content: parsed.content ?? "",
          replyToMessageId: parsed.replyToMessageId,
          attachmentMediaIds: parsed.attachmentMediaIds,
        });
        return NextResponse.json<ApiResponse>(
          { success: true, data: message },
          { status: 201 }
        );
      } catch (error) {
        if (error instanceof ZodError) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: error.errors[0]?.message ?? "Validation error" },
            { status: 400 }
          );
        }
        return handleApiError(error);
      }
    });
  })(request);
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const userId = authReq.user!.userId;
        const { searchParams } = new URL(authReq.url);
        const messageId = searchParams.get("messageId");
        if (!messageId) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: "messageId is required" },
            { status: 400 }
          );
        }

        const deleted = await deleteMessage(id, messageId, userId);
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

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const userId = authReq.user!.userId;
        const { searchParams } = new URL(authReq.url);
        const messageId = searchParams.get("messageId");
        if (!messageId) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: "messageId is required" },
            { status: 400 }
          );
        }
        const body = await authReq.json();
        const content = typeof body?.content === "string" ? body.content : "";
        const updated = await editMessage(id, messageId, userId, content);
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
