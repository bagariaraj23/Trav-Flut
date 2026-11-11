import { NextRequest, NextResponse } from "next/server";
import { UserSafetyAction } from "@prisma/client";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { listSafetyActions } from "@/lib/services/userSafety";
import { ApiResponse } from "@/types/api";
import { ValidationError } from "@/lib/errors";

export async function GET(request: NextRequest) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const actionParam = authReq.nextUrl.searchParams.get("action");
        if (actionParam !== "RESTRICT" && actionParam !== "BLOCK") {
          throw new ValidationError("action must be RESTRICT or BLOCK");
        }
        const limitParam = authReq.nextUrl.searchParams.get("limit");
        const cursor = authReq.nextUrl.searchParams.get("cursor") ?? undefined;
        const limit = limitParam ? Number(limitParam) : undefined;
        const data = await listSafetyActions(
          authReq.user!.userId,
          actionParam as UserSafetyAction,
          { limit, cursor }
        );
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
