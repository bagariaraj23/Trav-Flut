import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { removeGroupParticipant, promoteToAdmin } from "@/lib/services/chat";
import { ApiResponse } from "@/types/api";
import { z } from "zod";

const updateRoleSchema = z.object({
  role: z.enum(["ADMIN"]),
});

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; userId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: conversationId, userId: targetUserId } = await params;
        const adminUserId = authReq.user!.userId;

        const updated = await removeGroupParticipant(conversationId, adminUserId, targetUserId);

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

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; userId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: conversationId, userId: targetUserId } = await params;
        const adminUserId = authReq.user!.userId;
        const body = await authReq.json();
        const parsed = updateRoleSchema.parse(body);

        let updated;
        if (parsed.role === "ADMIN") {
          updated = await promoteToAdmin(conversationId, adminUserId, targetUserId);
        } else {
          throw new Error("Invalid role specified");
        }

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
