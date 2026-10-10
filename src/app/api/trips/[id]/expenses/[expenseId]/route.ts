import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { ApiResponse } from "@/types/api";
import { deleteExpense } from "@/lib/services/expense";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string; expenseId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: tripId, expenseId } = await params;
        const data = await deleteExpense({
          tripId,
          expenseId,
          actorId: authReq.user!.userId,
        });
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        return handleApiError(error, {
          endpoint: "DELETE /trips/[id]/expenses/[expenseId]",
          userId: authReq.user?.userId,
        });
      }
    });
  })(request);
}
