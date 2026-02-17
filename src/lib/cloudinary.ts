import { v2 as cloudinary } from "cloudinary";
import { randomUUID } from "crypto";
import { MediaType } from "@prisma/client";
import { AppError, ValidationError } from "./errors";
import { validateFileUpload } from "./security";
import { prisma } from "./prisma";

const requiredEnvVars = [
  "CLOUDINARY_CLOUD_NAME",
  "CLOUDINARY_API_KEY",
  "CLOUDINARY_API_SECRET",
];

const missingEnvVars = requiredEnvVars.filter(
  (name) => !process.env[name] || process.env[name]?.startsWith("your_")
);

if (missingEnvVars.length > 0) {
  console.warn(
    `⚠️  Cloudinary environment variables are missing or invalid: ${missingEnvVars.join(
      ", "
    )}. Media uploads will fail until these are configured.`
  );
} else {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
    secure: true,
  });
}

const CLOUDINARY_UPLOAD_FOLDER =
  process.env.CLOUDINARY_UPLOAD_FOLDER || "tripthread_uploads";

const ALLOWED_FORMATS_BY_RESOURCE_TYPE: Record<string, string[]> = {
  image: ["jpeg", "jpg", "png", "gif"],
  video: ["mp4", "mov", "avi"],
};

const USER_STORAGE_QUOTA_BYTES =
  Number(
    process.env.MEDIA_TOTAL_STORAGE_LIMIT_BYTES ?? 5 * 1024 * 1024 * 1024
  ) || 0;

function detectMimeType(buffer: Buffer): string | null {
  if (buffer.length >= 3) {
    if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
      return "image/jpeg";
    }
  }

  if (buffer.length >= 8) {
    const pngHeader = Buffer.from([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
    ]);
    if (buffer.subarray(0, 8).equals(pngHeader)) {
      return "image/png";
    }
  }

  if (buffer.length >= 6) {
    const signature = buffer.subarray(0, 6).toString("ascii");
    if (signature == "GIF87a" || signature == "GIF89a") {
      return "image/gif";
    }
  }

  if (buffer.length >= 12) {
    const brand = buffer.subarray(4, 8).toString("ascii");
    if (brand === "ftyp") {
      const majorBrand = buffer.subarray(8, 12).toString("ascii");
      if (["qt  ", "M4V "].includes(majorBrand)) {
        return "video/mov";
      }
      return "video/mp4";
    }
  }

  if (buffer.length >= 12) {
    const riff = buffer.subarray(0, 4).toString("ascii");
    const avi = buffer.subarray(8, 12).toString("ascii");
    if (riff === "RIFF" && avi === "AVI ") {
      return "video/avi";
    }
  }

  return null;
}

export type MediaUploadUsage = "trip_cover" | "thread_entry" | "general";

interface UploadSignatureArgs {
  filename: string;
  contentType: string;
  userId: string;
  tripId?: string;
  usage?: MediaUploadUsage;
}

interface ConfirmUploadArgs {
  url: string;
  secure_url: string;
  public_id: string;
  format: string;
  resource_type: string;
  bytes: number;
  original_filename: string;
  width?: number;
  height?: number;
  duration?: number;
  tripId?: string;
  usage?: MediaUploadUsage;
}

interface SignedUploadParams {
  signature: string;
  timestamp: number;
  apiKey: string;
  cloudName: string;
  folder: string;
  publicId: string;
  resourceType: "auto";
  uploadUrl: string;
}

function ensureConfigured(): void {
  if (missingEnvVars.length > 0) {
    throw new AppError(
      "Cloudinary is not configured. Please contact support.",
      500
    );
  }
}

export class CloudinaryService {
  /**
   * Generates signed parameters for a direct upload to Cloudinary.
   */
  static async generateUploadSignature(
    args: UploadSignatureArgs
  ): Promise<SignedUploadParams> {
    ensureConfigured();

    const { filename, contentType, userId, tripId, usage = "general" } = args;

    const validationResult = validateFileUpload({
      name: filename,
      type: contentType,
      size: 1, // We validate size on confirm; this is to validate name & mime upfront
    });

    if (!validationResult.isValid) {
      throw new ValidationError(validationResult.errors.join(", "));
    }

    const timestamp = Math.round(Date.now() / 1000);
    const resourceFolderParts = [CLOUDINARY_UPLOAD_FOLDER, userId];

    if (tripId) {
      resourceFolderParts.push(tripId);
    }

    resourceFolderParts.push(usage);

    const folder = resourceFolderParts.join("/");
    const baseName = filename.replace(/\.[^/.]+$/, "");
    const sanitizedBaseName = baseName
      .replace(/[\s()[\]{}'"]/g, "_")
      .replace(/[^a-zA-Z0-9_-]/g, "")
      .replace(/_{2,}/g, "_")
      .replace(/^_+|_+$/g, "")
      .slice(0, 60);
    const uniqueSlug = `${timestamp}_${randomUUID()}_${sanitizedBaseName}`;

    const paramsToSign: Record<string, string | number> = {
      folder,
      public_id: uniqueSlug,
      timestamp,
    };

    const signature = cloudinary.utils.api_sign_request(
      paramsToSign,
      process.env.CLOUDINARY_API_SECRET!
    );

    return {
      signature,
      timestamp,
      apiKey: process.env.CLOUDINARY_API_KEY!,
      cloudName: process.env.CLOUDINARY_CLOUD_NAME!,
      folder,
      publicId: uniqueSlug,
      resourceType: "auto",
      uploadUrl: `https://api.cloudinary.com/v1_1/${process.env.CLOUDINARY_CLOUD_NAME}/auto/upload`,
    };
  }

  /**
   * Validates the Cloudinary response payload and persists a Media record.
   */
  static async confirmUpload(
    data: ConfirmUploadArgs,
    userId: string
  ): Promise<{
    media: Awaited<ReturnType<typeof prisma.media.create>>;
  }> {
    ensureConfigured();

    if (!data.secure_url || !data.public_id) {
      throw new ValidationError(
        "Cloudinary response is missing required fields"
      );
    }

    if (
      !data.secure_url.startsWith(
        `https://res.cloudinary.com/${process.env.CLOUDINARY_CLOUD_NAME}/`
      )
    ) {
      throw new ValidationError("Unexpected Cloudinary URL");
    }

    const mimeType = `${data.resource_type}/${data.format}`;
    const validationResult = validateFileUpload({
      name: data.original_filename,
      type: mimeType,
      size: data.bytes,
    });

    if (!validationResult.isValid) {
      throw new ValidationError(
        `Upload failed validation: ${validationResult.errors.join(", ")}`
      );
    }

    const resourceTypeKey = data.resource_type.toLowerCase();
    const formatLower = data.format.toLowerCase();
    const allowedFormats = ALLOWED_FORMATS_BY_RESOURCE_TYPE[resourceTypeKey];

    if (!allowedFormats || !allowedFormats.includes(formatLower)) {
      throw new ValidationError(
        `Unsupported media format: ${resourceTypeKey}/${formatLower}`
      );
    }

    const mimeOverrides: Record<string, string> = {
      jpg: "image/jpeg",
      jpeg: "image/jpeg",
      png: "image/png",
      gif: "image/gif",
      mp4: "video/mp4",
      mov: "video/quicktime",
      avi: "video/avi",
    };

    const expectedMime = mimeOverrides[formatLower] ?? mimeType.toLowerCase();

    const mediaType =
      data.resource_type.toUpperCase() === "VIDEO"
        ? MediaType.VIDEO
        : MediaType.IMAGE;

    // Verify reported mime type using magic number
    let verificationPassed = false;
    try {
      const response = await fetch(data.secure_url, {
        method: "GET",
        headers: { Range: "bytes=0-511" },
        cache: "no-store",
      });

      if (response.ok) {
        const buffer = Buffer.from(await response.arrayBuffer());
        const detected = detectMimeType(buffer);
        if (detected) {
          if (detected.toLowerCase() !== expectedMime) {
            throw new ValidationError(
              `File content mismatch. Expected ${expectedMime} but received ${detected}.`
            );
          }
          verificationPassed = true;
        } else {
          console.warn(
            "[Cloudinary] Unable to determine mime type from file header."
          );
        }
      } else {
        console.warn(
          "[Cloudinary] Unable to fetch file head for content verification:",
          response.status,
          response.statusText
        );
      }
    } catch (error) {
      console.warn("[Cloudinary] Magic number verification failed:", error);
      if (error instanceof ValidationError) {
        throw error;
      }
    }

    if (!verificationPassed) {
      console.warn(
        "[Cloudinary] Proceeding without header verification; ensuring type via Cloudinary metadata."
      );
    }

    if (USER_STORAGE_QUOTA_BYTES > 0) {
      const currentUsage = await prisma.media.aggregate({
        _sum: { size: true },
        where: { uploadedById: userId },
      });
      const usedBytes = currentUsage._sum.size ?? 0;
      if (usedBytes + data.bytes > USER_STORAGE_QUOTA_BYTES) {
        throw new ValidationError(
          "Storage quota exceeded. Delete existing media before uploading new files."
        );
      }
    }

    const media = await prisma.media.create({
      data: {
        url: data.secure_url,
        publicId: data.public_id,
        type: mediaType,
        filename: data.original_filename,
        size: data.bytes,
        width: data.width ?? null,
        height: data.height ?? null,
        duration: data.duration ?? null,
        processingStatus: "COMPLETED",
        uploadedById: userId,
        tripId: data.tripId ?? null,
      } as any,
    });

    return { media };
  }

  static async deleteMedia(publicId: string): Promise<void> {
    ensureConfigured();
    await cloudinary.uploader.destroy(publicId);
    await prisma.media.deleteMany({ where: { publicId } });
  }

  static async cleanupOrphanedMedia(userId: string): Promise<void> {
    try {
      const staleThreshold = new Date(Date.now() - 1000 * 60 * 60 * 24); // 24 hours
      const staleMedia = await prisma.media.findMany({
        where: {
          uploadedById: userId,
          tripId: null,
          threadEntries: { none: {} },
          createdAt: { lt: staleThreshold },
        },
        select: { publicId: true },
        take: 5,
      });

      for (const media of staleMedia) {
        try {
          await CloudinaryService.deleteMedia(media.publicId);
        } catch (cleanupError) {
          console.error(
            "[Cloudinary] Failed to clean up stale media:",
            cleanupError
          );
        }
      }
    } catch (error) {
      console.error("[Cloudinary] Cleanup orphaned media failed:", error);
    }
  }
}
