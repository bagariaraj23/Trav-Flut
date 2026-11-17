import { NextRequest, NextResponse } from "next/server";
import { UserSafetyAction } from "@prisma/client";
import { z } from "zod";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import {
  clearSafetyAction,
  getSafetyPair,
  setSafetyAction,
} from "@/lib/services/userSafety";
import { ApiResponse } from "@/types/api";

const bodySchema = z.object({
  action: z.enum(["RESTRICT", "BLOCK"]),
});

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const data = await getSafetyPair(authReq.user!.userId, id);
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        const body = bodySchema.parse(await authReq.json());
        const data = await setSafetyAction(
          authReq.user!.userId,
          id,
          body.action as UserSafetyAction
        );
        return NextResponse.json<ApiResponse>({ success: true, data });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authReq) => {
      try {
        const { id } = await params;
        await clearSafetyAction(authReq.user!.userId, id);
        return NextResponse.json<ApiResponse>({ success: true });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}
