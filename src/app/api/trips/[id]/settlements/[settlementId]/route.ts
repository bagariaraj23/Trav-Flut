import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { ApiResponse } from "@/types/api";
import { undoSettlement } from "@/lib/services/expense";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; settlementId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: tripId, settlementId } = await params;
        const data = await undoSettlement({
          tripId,
          settlementId,
          actorId: authReq.user!.userId,
        });
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        return handleApiError(error, {
          endpoint: "DELETE /trips/[id]/settlements/[settlementId]",
          userId: authReq.user?.userId,
        });
      }
    });
  })(request);
}
