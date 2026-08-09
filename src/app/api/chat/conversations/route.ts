import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import {
  createConversation,
  listConversations,
  type CreateConversationParams,
} from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";
import { z } from "zod";

const createBodySchema = z.object({
  type: z.enum(["DM", "GROUP", "TRIP"]),
  participantIds: z.array(z.string().uuid()).min(0),
  name: z.string().max(255).optional().nullable(),
  tripId: z.string().uuid().optional().nullable(),
});

export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const userId = authReq.user!.userId;
        const { searchParams } = new URL(authReq.url);
        const tripId = searchParams.get("tripId") ?? undefined;
        const list = await listConversations(userId, { tripId });
        return NextResponse.json<ApiResponse>(
          { success: true, data: { conversations: list } },
          { status: 200 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}

export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const userId = authReq.user!.userId;
        const body = await authReq.json();
        const parsed = createBodySchema.parse(body) as CreateConversationParams;
        const conversation = await createConversation(parsed, userId);
        return NextResponse.json<ApiResponse>(
          { success: true, data: conversation },
          { status: 201 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
