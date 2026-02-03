import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { withEngagementRateLimit } from "@/lib/middleware";
import { createCommentSchema } from "@/lib/validation";
import { createComment } from "@/lib/services/comment";
import { canCommentOnEntity } from "@/lib/auth/permissions";
import { moderateContent } from "@/lib/security/moderation";
import { logSecurityEvent } from "@/lib/security/events";
import { ApiResponse } from "@/types/api";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withEngagementRateLimit(req, async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const body = await rateLimitedReq.json();
          const validatedData = createCommentSchema.parse(body);
          const userId = authenticatedReq.user!.userId;

          const canComment = await canCommentOnEntity(
            userId,
            validatedData.entityType,
            validatedData.entityId
          );

          if (!canComment) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "Entity not found or access denied",
              },
              { status: 404 }
            );
          }

          const moderation = moderateContent(validatedData.contentText);

          if (moderation.hasProfanity) {
            await logSecurityEvent({
              eventType: 'PROFANITY_DETECTED',
              userId,
              entityType: validatedData.entityType,
              entityId: validatedData.entityId,
              ipAddress: request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || null,
              metadata: {
                originalLength: moderation.originalLength,
                sanitizedLength: moderation.sanitizedLength,
              },
            });
          }

          const comment = await createComment(
            userId,
            validatedData.entityType,
            validatedData.entityId,
            moderation.sanitized,
            validatedData.parentCommentId
          );

          return NextResponse.json<ApiResponse>({
            success: true,
            data: comment,
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
          if (
            error.message === "Entity not found" ||
            error.message === "Parent comment not found"
          ) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: error.message,
              },
              { status: 404 }
            );
          }
          if (error.message === "Nesting limited to one level only") {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: error.message,
              },
              { status: 400 }
            );
          }
          return handleApiError(error);
        }
      });
    }, 'comment');
  });
  
  return await loggedHandler(request);
}

