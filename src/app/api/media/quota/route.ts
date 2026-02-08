import { NextRequest } from "next/server";
import { ok, serverError } from "@/lib/response-helpers";
import { withAuth, AuthenticatedRequest } from "@/lib/middleware";
import { prisma } from "@/lib/prisma";

async function handler(request: AuthenticatedRequest) {
  try {
    const userId = request.user!.userId;

    // Get total storage used
    const storageUsage = await prisma.media.aggregate({
      _sum: { size: true },
      where: { uploadedById: userId },
    });

    // Get today's upload count
    const startOfDay = new Date();
    startOfDay.setUTCHours(0, 0, 0, 0);
    const dailyUploads = await prisma.media.count({
      where: {
        uploadedById: userId,
        createdAt: { gte: startOfDay },
      },
    });

    // Get total media count
    const totalMedia = await prisma.media.count({
      where: { uploadedById: userId },
    });

    const dailyLimit = Number(process.env.MEDIA_DAILY_UPLOAD_LIMIT ?? 200) || 0;
    const storageQuota =
      Number(
        process.env.MEDIA_TOTAL_STORAGE_LIMIT_BYTES ?? 5 * 1024 * 1024 * 1024
      ) || 0;

    return ok({
      storage: {
        used: storageUsage._sum.size ?? 0,
        quota: storageQuota,
        percentUsed:
          storageQuota > 0
            ? Math.round(((storageUsage._sum.size ?? 0) / storageQuota) * 100)
            : 0,
      },
      daily: {
        uploaded: dailyUploads,
        limit: dailyLimit,
        remaining:
          dailyLimit > 0 ? Math.max(0, dailyLimit - dailyUploads) : null,
      },
      total: {
        mediaCount: totalMedia,
      },
    });
  } catch (error: any) {
    console.error("[MEDIA] Get quota failed:", error);
    return serverError("Failed to retrieve media quota");
  }
}

export async function GET(request: NextRequest) {
  return withAuth(request, handler);
}
