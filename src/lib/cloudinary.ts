import { v2 as cloudinary } from "cloudinary";
import { randomUUID } from "crypto";
import { MediaType } from "@prisma/client";
import { AppError, ValidationError } from "./errors";
import { validateFileUpload } from "./security";
import { prisma } from "./db";

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
  process.env.CLOUDINARY_UPLOAD_FOLDER || "trav-flut/uploads";

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
    const sanitizedContentType = contentType.toLowerCase();
    const resourceFolderParts = [CLOUDINARY_UPLOAD_FOLDER, userId];

    if (tripId) {
      resourceFolderParts.push(tripId);
    }

    resourceFolderParts.push(usage);

    const folder = resourceFolderParts.join("/");
    const baseName = filename.replace(/\.[^/.]+$/, "");
    const sanitizedBaseName =
      baseName.length > 60 ? baseName.slice(0, 60) : baseName;
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
      throw new ValidationError("Cloudinary response is missing required fields");
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

    const mediaType =
      data.resource_type.toUpperCase() === "VIDEO"
        ? MediaType.VIDEO
        : MediaType.IMAGE;

    const media = await prisma.media.create({
      data: {
        url: data.secure_url,
        publicId: data.public_id,
        type: mediaType,
        filename: data.original_filename,
        size: data.bytes,
        uploadedById: userId,
        tripId: data.tripId ?? null,
      },
    });

    return { media };
  }

  static async deleteMedia(publicId: string): Promise<void> {
    ensureConfigured();
    await cloudinary.uploader.destroy(publicId);
    await prisma.media.deleteMany({ where: { publicId } });
  }
}
