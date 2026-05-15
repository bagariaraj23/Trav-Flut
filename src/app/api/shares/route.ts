import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { withEngagementRateLimit } from "@/lib/middleware";
import { createShareSchema } from "@/lib/validation";
import { createShare } from "@/lib/services/share";
import { canShareEntity } from "@/lib/auth/permissions";
import { ApiResponse } from "@/types/api";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withEngagementRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const body = await rateLimitedReq.json();
          const validatedData = createShareSchema.parse(body);
          const userId = authenticatedReq.user!.userId;

          const canShare = await canShareEntity(
            userId,
            validatedData.entityType,
            validatedData.entityId
          );

          if (!canShare) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Entity not found or access denied",
              },
              { status: 404 }
            );
          }

          const share = await createShare(
            userId,
            validatedData.entityType,
            validatedData.entityId,
            validatedData.shareType,
            validatedData.expiresAt,
            validatedData.shareSource
          );

          return NextResponse.json<ApiResponse>({
            success: true,
            data: share,
          });
        } catch (error: any) {
          if (error.name === "ZodError") {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: error.errors[0]?.message || "Validation error",
              },
              { status: 400 }
            );
          }
          if (error.message === "Entity not found") {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Entity not found",
              },
              { status: 404 }
            );
          }
          return handleApiError(error);
        }
      });
    }, 'share');
  });
  
  return await loggedHandler(request);
}

