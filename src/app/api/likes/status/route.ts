import { NextRequest, NextResponse } from "next/server";
import { withAuth, withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { checkLikeStatus } from "@/lib/services/like";
import { ApiResponse } from "@/types/api";
import { EntityType } from "@prisma/client";
import { z } from "zod";

const statusQuerySchema = z.object({
  entityType: z.enum(["TRIP_FINAL_POST", "TRIP_THREAD_ENTRY", "COMMENT"]),
  entityIds: z.string().transform((val) => {
    if (typeof val === "string") {
      return val.split(",").filter(Boolean);
    }
    return Array.isArray(val) ? val : [];
  }),
});

export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const { searchParams } = new URL(authenticatedReq.url);
          const entityType = searchParams.get("entityType");
          const entityIdsParam = searchParams.get("entityIds");

          if (!entityType || !entityIdsParam) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "entityType and entityIds are required",
              },
              { status: 400 }
            );
          }

          const validatedData = statusQuerySchema.parse({
            entityType,
            entityIds: entityIdsParam,
          });

          if (validatedData.entityIds.length === 0) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "At least one entityId is required",
              },
              { status: 400 }
            );
          }

          if (validatedData.entityIds.length > 100) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Maximum 100 entityIds allowed",
              },
              { status: 400 }
            );
          }

          const userId = authenticatedReq.user!.userId;
          const result = await checkLikeStatus(
            userId,
            validatedData.entityType as EntityType,
            validatedData.entityIds
          );

          return NextResponse.json<ApiResponse>({
            success: true,
            data: result,
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
          return handleApiError(error);
        }
      });
    });
  });
  
  return await loggedHandler(request);
}

