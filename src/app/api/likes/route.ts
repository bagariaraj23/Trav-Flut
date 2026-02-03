import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { withEngagementRateLimit } from "@/lib/middleware";
import { createLikeSchema, deleteLikeSchema } from "@/lib/validation";
import { createLike, deleteLike } from "@/lib/services/like";
import { canLikeEntity } from "@/lib/auth/permissions";
import { ApiResponse } from "@/types/api";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
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
  });
  
  return await loggedHandler(request);
}

export async function DELETE(request: NextRequest) {
  return withLogging(async (req) => {
    return withEngagementRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const { searchParams } = new URL(rateLimitedReq.url);
          const entityType = searchParams.get('entityType');
          const entityId = searchParams.get('entityId');

          if (!entityType || !entityId) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "entityType and entityId are required query parameters",
              },
              { status: 400 }
            );
          }

          const validatedData = deleteLikeSchema.parse({ entityType, entityId });
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

          const result = await deleteLike(userId, validatedData.entityType, validatedData.entityId);

          if (!result) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Like not found",
              },
              { status: 404 }
            );
          }

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
  });
}

