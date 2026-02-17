import { NextRequest, NextResponse } from "next/server";
import { withAuth, withLogging, handleApiError } from "@/lib/middleware";
import { deleteLike } from "@/lib/services/like";
import { logSecurityEvent } from "@/lib/security/events";
import { prisma } from "@/lib/prisma";
import { ApiResponse } from "@/types/api";
import { EntityType } from "@prisma/client";

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ entityType: string; entityId: string }> }
) {
  const loggedHandler = withLogging(async (req) => {
    return withAuth(req, async (authenticatedReq) => {
      try {
        const { entityType, entityId } = await params;
        const userId = authenticatedReq.user!.userId;

        if (!Object.values(EntityType).includes(entityType as EntityType)) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Invalid entity type",
            },
            { status: 400 }
          );
        }

        const like = await prisma.like.findFirst({
          where: {
            userId,
            entityType: entityType as EntityType,
            entityId,
          },
        });

        if (!like) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Like not found",
            },
            { status: 404 }
          );
        }

        if (like.userId !== userId) {
          await logSecurityEvent({
            eventType: "UNAUTHORIZED_ACCESS",
            userId,
            entityType: entityType as EntityType,
            entityId,
            ipAddress:
              request.headers.get("x-forwarded-for") ||
              request.headers.get("x-real-ip") ||
              null,
            metadata: { action: "delete_like", likeId: like.id },
          });

          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Forbidden",
            },
            { status: 403 }
          );
        }

        const result = await deleteLike(
          userId,
          entityType as EntityType,
          entityId
        );

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
      } catch (error) {
        return handleApiError(error);
      }
    });
  });

  return await loggedHandler(request);
}
