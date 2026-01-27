import { NextRequest, NextResponse } from "next/server";
import { withRateLimit, withLogging, handleApiError } from "@/lib/middleware";
import { prisma } from "@/lib/prisma";
import { ApiResponse } from "@/types/api";
import { EntityType } from "@prisma/client";

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ entityType: string; entityId: string }> }
) {
  return withLogging(async (req) => {
    return withRateLimit(req, async (rateLimitedReq) => {
      try {
        const { entityType, entityId } = await params;

        if (!Object.values(EntityType).includes(entityType as EntityType)) {
          return NextResponse.json<ApiResponse>(
            {
              success: false,
              error: "Invalid entity type",
            },
            { status: 400 }
          );
        }

        let shareCount = 0;

        interface ShareMetadata {
          totalShares: number;
          totalOpens: number;
          platforms: Record<string, number>;
        }
        let metadata: ShareMetadata | null = null;

        if (entityType === "TRIP_FINAL_POST") {
          const post = await prisma.tripFinalPost.findUnique({
            where: { id: entityId },
            select: { shareCount: true },
          });
          shareCount = post?.shareCount || 0;
        }

        const shares = await prisma.share.findMany({
          where: {
            entityType: entityType as EntityType,
            entityId,
          },
          select: {
            metadata: true,
            createdAt: true,
          },
          take: 100,
        });

        if (shares.length > 0) {
          const allOpens = shares.flatMap((share) => {
            const meta = share.metadata as any;
            return meta?.opens || [];
          });
          metadata = {
            totalShares: shares.length,
            totalOpens: allOpens.length,
            platforms: allOpens.reduce((acc: any, open: any) => {
              const platform = open.platform || "unknown";
              acc[platform] = (acc[platform] || 0) + 1;
              return acc;
            }, {}),
          };
        }

        return NextResponse.json<ApiResponse>({
          success: true,
          data: {
            shareCount,
            metadata,
          },
        });
      } catch (error) {
        return handleApiError(error);
      }
    });
  })(request);
}

