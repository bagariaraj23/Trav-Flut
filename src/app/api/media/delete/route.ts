import { NextRequest } from "next/server";
import { z } from "zod";
import { ok, badRequest, forbidden, serverError } from "@/lib/response-helpers";
import {
  withAuth,
  AuthenticatedRequest,
} from "@/lib/middleware";
import { CloudinaryService } from "@/lib/cloudinary";
import { prisma } from "@/lib/db";

const deleteSchema = z.object({
  publicId: z.string().min(1),
});

async function handler(request: AuthenticatedRequest) {
  try {
    const body = await request.json();
    const { publicId } = deleteSchema.parse(body);
    const userId = request.user!.userId;

    const mediaRecord = await prisma.media.findUnique({
      where: { publicId },
      select: { uploadedById: true },
    });

    if (mediaRecord) {
      if (mediaRecord.uploadedById !== userId) {
        return forbidden("You do not have permission to delete this media");
      }
    } else if (!publicId.includes(`/${userId}/`)) {
      return forbidden("You do not have permission to delete this media");
    }

    await CloudinaryService.deleteMedia(publicId);

    return ok(null, "Media deleted successfully");
  } catch (error: any) {
    console.error("[MEDIA] Delete upload failed:", error);

    if (error.name === "ZodError") {
      return badRequest("Invalid request data", error.errors);
    }

    return serverError("Failed to delete media");
  }
}

export async function POST(request: NextRequest) {
  return withAuth(request, handler);
}

