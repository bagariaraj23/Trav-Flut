import { NextRequest, NextResponse } from "next/server";
import { ZodError } from "zod";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { createExpenseSchema, paginationSchema } from "@/lib/validation";
import { ApiResponse, TripExpenseListResponse, TripExpenseResponse } from "@/types/api";
import { createExpense, listExpenses } from "@/lib/services/expense";
import { AppError } from "@/lib/errors";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id: tripId } = await params;
        const url = new URL(req.url);
        const pageLimit = paginationSchema.parse({
          page: url.searchParams.get("page") ?? "1",
          limit: url.searchParams.get("limit") ?? "20",
        });
        const data = await listExpenses({
          tripId,
          actorId: authReq.user!.userId,
          page: pageLimit.page,
          limit: pageLimit.limit,
        });
        return NextResponse.json<ApiResponse<TripExpenseListResponse>>({
          success: true,
          data,
        });
      } catch (error) {
        if (error instanceof ZodError) {
          return NextResponse.json<ApiResponse>(
            { success: false, error: error.issues[0]?.message || "Invalid query" },
            { status: 400 }
          );
        }
        return handleApiError(error, {
          endpoint: "GET /trips/[id]/expenses",
          userId: authReq.user?.userId,
        });
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
        const { id: tripId } = await params;
        const body = await req.json();
        const input = createExpenseSchema.parse(body);
        const data = await createExpense({
          tripId,
          actorId: authReq.user!.userId,
          input,
        });
        return NextResponse.json<ApiResponse<TripExpenseResponse>>(
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
        if (error instanceof AppError) {
          return handleApiError(error, {
            endpoint: "POST /trips/[id]/expenses",
            userId: authReq.user?.userId,
          });
        }
        return handleApiError(error, {
          endpoint: "POST /trips/[id]/expenses",
          userId: authReq.user?.userId,
        });
      }
    });
  })(request);
}
