import { NextRequest } from "next/server";
import { z } from "zod";
import { ok, badRequest, serverError } from "@/lib/response-helpers";
import {
  withAuth,
  AuthenticatedRequest,
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

    const uploadParams = await CloudinaryService.generateUploadSignature({
      filename,
      contentType,
      userId: request.user!.userId,
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
  return withAuth(request, handler);
}
