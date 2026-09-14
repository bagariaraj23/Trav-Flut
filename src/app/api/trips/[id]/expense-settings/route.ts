import { NextRequest, NextResponse } from "next/server";
import { ZodError } from "zod";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { updateExpenseSettingsSchema } from "@/lib/validation";
import { ApiResponse } from "@/types/api";
import { updateExpenseSettings } from "@/lib/services/expense";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: tripId } = await params;
        const body = await req.json();
        const input = updateExpenseSettingsSchema.parse(body);
        const data = await updateExpenseSettings({
          tripId,
          actorId: authReq.user!.userId,
          expenseCurrency: input.expenseCurrency,
          spendVisibleOnDiscover: input.spendVisibleOnDiscover,
        });
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        if (error instanceof ZodError) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: error.issues[0]?.message || "Validation error" },
            { status: 400 }
          );
        }
        return handleApiError(error, {
          endpoint: "PATCH /trips/[id]/expense-settings",
          userId: authReq.user?.userId,
        });
      }
    });
  })(request);
}
