import { NextRequest, NextResponse } from "next/server";
import { validateTripStatus, TripConflictInfo } from "@/lib/tripValidation";
import {
  withAuth,
  AuthenticatedRequest,
  handleApiError,
} from "@/lib/middleware";
import { ApiResponse } from "@/types/api";

async function handler(request: AuthenticatedRequest) {
  try {
    const userId = request.user!.userId;
    const conflictInfo = await validateTripStatus(userId);

    return NextResponse.json<ApiResponse<TripConflictInfo>>({
      success: true,
      data: conflictInfo,
    });
  } catch (error) {
    return handleApiError(error);
  }
}

export async function GET(request: NextRequest) {
  return withAuth(request, (authRequest) => handler(authRequest));
}

