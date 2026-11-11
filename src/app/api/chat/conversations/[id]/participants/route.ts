import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { addGroupParticipant } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";
import { z } from "zod";

const addParticipantSchema = z.object({
  userId: z.string().uuid(),
});

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const adminUserId = authReq.user!.userId;
        const body = await authReq.json();
        const parsed = addParticipantSchema.parse(body);

        const updated = await addGroupParticipant(id, adminUserId, parsed.userId);

        return NextResponse.json<ApiResponse>(
          { success: true, data: updated },
          { status: 201 }
        );
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
