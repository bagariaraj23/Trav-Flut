import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { updateComment, deleteComment } from "@/lib/services/comment";
import { canEditComment, canDeleteComment } from "@/lib/auth/permissions";
import { moderateContent } from "@/lib/security/moderation";
import { logSecurityEvent } from "@/lib/security/events";
import { ApiResponse } from "@/types/api";
import { z } from "zod";

const updateCommentSchema = z.object({
  contentText: z
    .string()
    .min(1, "Comment must be at least 1 character")
    .max(500, "Comment must be less than 500 characters")
    .transform((text) => text.trim())
    .refine((text) => text.length > 0, {
      message: "Comment cannot be empty or only whitespace",
    }),
});

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ commentId: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withAuth(req, async (authenticatedReq) => {
      try {
        const { commentId } = await params;
        const body = await authenticatedReq.json();
        const validatedData = updateCommentSchema.parse(body);
        const userId = authenticatedReq.user!.userId;

        const canEdit = await canEditComment(userId, commentId);

        if (!canEdit) {
          await logSecurityEvent({
            eventType: 'UNAUTHORIZED_ACCESS',
            userId,
            entityType: 'COMMENT',
            entityId: commentId,
            ipAddress: request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || null,
            metadata: { action: 'edit_comment' },
          });

          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Forbidden: You can only edit your own comments within 15 minutes of creation",
            },
            { status: 403 }
          );
        }

        const moderation = moderateContent(validatedData.contentText);

        if (moderation.hasProfanity) {
          await logSecurityEvent({
            eventType: 'PROFANITY_DETECTED',
            userId,
            entityType: 'COMMENT',
            entityId: commentId,
            ipAddress: request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || null,
            metadata: {
              originalLength: moderation.originalLength,
              sanitizedLength: moderation.sanitizedLength,
            },
          });
        }

        const comment = await updateComment(userId, commentId, moderation.sanitized);

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
        if (error.message === "Comment not found") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Comment not found",
            },
            { status: 404 }
          );
        }
        return handleApiError(error);
      }
    });
  });
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ commentId: string }> }
) {
  return withLogging(async (req) => {
    return withAuth(req, async (authenticatedReq) => {
      try {
        const { commentId } = await params;
        const userId = authenticatedReq.user!.userId;

        const canDelete = await canDeleteComment(userId, commentId);

        if (!canDelete) {
          await logSecurityEvent({
            eventType: 'UNAUTHORIZED_ACCESS',
            userId,
            entityType: 'COMMENT',
            entityId: commentId,
            ipAddress: request.headers.get('x-forwarded-for') || request.headers.get('x-real-ip') || null,
            metadata: { action: 'delete_comment' },
          });

          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Forbidden",
            },
            { status: 403 }
          );
        }

        await deleteComment(userId, commentId);

        return NextResponse.json<ApiResponse>({
          success: true,
          data: null,
        });
      } catch (error: any) {
        if (error.message === "Comment not found") {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Comment not found",
            },
            { status: 404 }
          );
        }
        return handleApiError(error);
      }
    });
  });
}

