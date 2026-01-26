import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { withEngagementRateLimit } from "@/lib/middleware";
import { createLikeSchema } from "@/lib/validation";
import { createLike } from "@/lib/services/like";
import { canLikeEntity } from "@/lib/auth/permissions";
import { ApiResponse } from "@/types/api";

export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    return withEngagementRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const body = await rateLimitedReq.json();
          const validatedData = createLikeSchema.parse(body);
          const userId = authenticatedReq.user!.userId;

          const canLike = await canLikeEntity(
            userId,
            validatedData.entityType,
            validatedData.entityId
          );

          if (!canLike) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Entity not found or access denied",
              },
              { status: 404 }
            );
          }

          await createLike(userId, validatedData.entityType, validatedData.entityId);

          return NextResponse.json<ApiResponse>({
            success: true,
            data: null,
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
    }, 'like');
  })(request);
}

