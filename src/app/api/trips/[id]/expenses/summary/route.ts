import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { ApiResponse, ExpenseSummaryResponse } from "@/types/api";
import { getExpenseSummary } from "@/lib/services/expense";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: tripId } = await params;
        const data = await getExpenseSummary({
          tripId,
          actorId: authReq.user!.userId,
        });
        return NextResponse.json<ApiResponse<ExpenseSummaryResponse>>({
          success: true,
          data,
        });
      } catch (error) {
        return handleApiError(error, {
          endpoint: "GET /trips/[id]/expenses/summary",
          userId: authReq.user?.userId,
        });
      }
    });
  })(request);
}
