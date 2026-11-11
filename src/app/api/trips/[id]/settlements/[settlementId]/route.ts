import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { enforcePresetRateLimit } from "@/lib/rateLimit";
import { ApiResponse } from "@/types/api";
import { undoSettlement } from "@/lib/services/expense";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; settlementId: string }> }
) {
  const limited = await enforcePresetRateLimit(request, "write");
  if (limited) return limited;
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
