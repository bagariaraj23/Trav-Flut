import { NextRequest, NextResponse } from "next/server";
import { ZodError } from "zod";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { createSettlementSchema } from "@/lib/validation";
import { ApiResponse, RecordedSettlementResponse } from "@/types/api";
import { recordSettlement } from "@/lib/services/expense";

export async function POST(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: tripId } = await params;
        const body = await req.json();
        const input = createSettlementSchema.parse(body);
        const data = await recordSettlement({
          tripId,
          actorId: authReq.user!.userId,
          fromUserId: input.fromUserId,
          toUserId: input.toUserId,
          amountMinor: input.amountMinor,
        });
        return NextResponse.json<ApiResponse<RecordedSettlementResponse>>(
          { success: true, data },
          { status: 201 }
        );
      } catch (error) {
        if (error instanceof ZodError) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: error.issues[0]?.message || "Validation error" },
            { status: 400 }
          );
        }
        return handleApiError(error, {
          endpoint: "POST /trips/[id]/settlements",
          userId: authReq.user?.userId,
        });
      }
    });
  })(request);
}
