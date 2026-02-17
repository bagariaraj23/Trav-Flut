import { NextRequest } from "next/server";
import { z } from "zod";
import { ok, badRequest, serverError } from "@/lib/response-helpers";
import { withAuth, AuthenticatedRequest } from "@/lib/middleware";
import { prisma } from "@/lib/prisma";
import { CloudinaryService } from "@/lib/cloudinary";

const mediaUsageEnum = z.enum(["trip_cover", "thread_entry", "general"]);

const confirmSchema = z.object({
  url: z.string().url(),
  secure_url: z.string().url(),
  public_id: z.string().min(1),
  format: z.string().min(1),
  resource_type: z.string().min(1),
  bytes: z.number().positive(),
  original_filename: z.string().min(1),
  width: z.number().positive().optional(),
  height: z.number().positive().optional(),
  duration: z.number().positive().optional(),
  tripId: z.string().uuid().optional(),
  usage: mediaUsageEnum.default("general"),
});

async function handler(request: AuthenticatedRequest) {
  try {
    const body = await request.json();

    const { tripId, usage, ...cloudinaryPayload } = confirmSchema.parse(body);

    if (tripId) {
      const trip = await prisma.trip.findFirst({
        where: {
          id: tripId,
          OR: [
            { userId: request.user!.userId },
            {
              participants: {
                some: { userId: request.user!.userId },
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

    const { media } = await CloudinaryService.confirmUpload(
      {
        ...cloudinaryPayload,
        tripId,
        usage,
      },
      request.user!.userId
    );

    await CloudinaryService.cleanupOrphanedMedia(request.user!.userId);

    return ok(media, "Media upload confirmed successfully");
  } catch (error: any) {
    console.error("[MEDIA] Confirm upload failed:", error);

    // Log the full error details for debugging
    if (error.code) {
      console.error("[MEDIA] Prisma error code:", error.code);
    }
    if (error.meta) {
      console.error("[MEDIA] Prisma error meta:", error.meta);
    }

    if (error.name === "ZodError") {
      return badRequest("Invalid request data", error.errors);
    }
    if (error.name === "ValidationError") {
      return badRequest(error.message);
    }

    // Return more detailed error in development
    if (process.env.NODE_ENV === "development") {
      return serverError(`Failed to confirm media upload: ${error.message}`);
    }

    return serverError("Failed to confirm media upload");
  }
}

export async function POST(request: NextRequest) {
  return withAuth(request, handler);
}
