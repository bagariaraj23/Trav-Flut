import { NextRequest } from "next/server";
import { z } from "zod";
import { ok, badRequest, serverError } from "@/lib/response-helpers";
import {
  AuthenticatedRequest,
  withAuth,
  withRateLimit,
} from "@/lib/middleware";
import { prisma } from "@/lib/db";
import { CloudinaryService } from "@/lib/cloudinary";

const mediaUsageEnum = z.enum(["trip_cover", "thread_entry", "general"]);

const signatureSchema = z.object({
  filename: z.string().min(1).max(255),
  contentType: z.string().min(1).max(255),
  tripId: z.string().uuid().optional(),
  usage: mediaUsageEnum.default("general"),
});

async function handler(request: AuthenticatedRequest) {
  try {
    const body = await request.json();
    const { filename, contentType, tripId, usage } =
      signatureSchema.parse(body);
    const userId = request.user!.userId;

    if (tripId) {
      const trip = await prisma.trip.findFirst({
        where: {
          id: tripId,
          OR: [
            { userId },
            {
              participants: {
                some: { userId },
              },
            },
          ],
        },
        select: { id: true },
      });

      if (!trip) {
        return badRequest("Trip not found or access denied");
      }
    }

    const dailyLimit =
      Number(process.env.MEDIA_DAILY_UPLOAD_LIMIT ?? 200) || 0;

    if (dailyLimit > 0) {
      const startOfDay = new Date();
      startOfDay.setUTCHours(0, 0, 0, 0);

      const dailyUploads = await prisma.media.count({
        where: {
          uploadedById: userId,
          createdAt: { gte: startOfDay },
        },
      });

      if (dailyUploads >= dailyLimit) {
        return badRequest(
          "Daily media upload limit reached. Try again tomorrow."
        );
      }
    }

    const uploadParams = await CloudinaryService.generateUploadSignature({
      filename,
      contentType,
      userId,
      tripId,
      usage,
    });

    return ok(
      uploadParams,
      "Signed upload parameters generated successfully"
    );
  } catch (error: any) {
    console.error("[MEDIA] Signature generation failed:", error);

    if (error.name === "ZodError") {
      return badRequest("Invalid request data", error.errors);
    }

    if (error.name === "ValidationError") {
      return badRequest(error.message);
    }

    return serverError("Failed to generate upload signature");
  }
}

export async function POST(request: NextRequest) {
  return withRateLimit(
    request,
    (rateLimitedReq) => withAuth(rateLimitedReq, handler),
    { maxRequests: 20, windowMs: 60_000 }
  );
}
