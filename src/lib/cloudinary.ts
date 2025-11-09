import { v2 as cloudinary } from 'cloudinary';
import crypto from 'crypto';

// Check if required environment variables are set
const requiredEnvVars = {
  CLOUDINARY_CLOUD_NAME: process.env.CLOUDINARY_CLOUD_NAME,
  CLOUDINARY_API_KEY: process.env.CLOUDINARY_API_KEY,
  CLOUDINARY_API_SECRET: process.env.CLOUDINARY_API_SECRET,
};

// Validate environment variables
const missingVars = Object.entries(requiredEnvVars)
  .filter(([key, value]) => !value || value === 'your_actual_api_secret')
  .map(([key]) => key);

if (missingVars.length > 0) {
  console.warn(`⚠️  Missing or invalid Cloudinary environment variables: ${missingVars.join(', ')}`);
  console.warn('Cloudinary service will not work properly. Please set valid credentials in .env.local');
}

// Configure Cloudinary only if all required variables are present
if (missingVars.length === 0) {
  cloudinary.config({
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
    api_key: process.env.CLOUDINARY_API_KEY,
    api_secret: process.env.CLOUDINARY_API_SECRET,
  });
  console.log('✅ Cloudinary configured successfully');
} else {
  console.error('❌ Cloudinary configuration failed due to missing environment variables');
}

export { cloudinary };

// Helper function to generate signature for direct uploads
export function generateSignature(params: Record<string, any>): string {
  // Check if Cloudinary is properly configured
  if (missingVars.length > 0) {
    throw new Error('Cloudinary not configured. Please set all required environment variables.');
  }

  // Sort parameters alphabetically
  const sortedParams = Object.keys(params)
    .sort()
    .reduce((result: Record<string, any>, key) => {
      result[key] = params[key];
      return result;
    }, {});

  // Create query string
  const queryString = Object.entries(sortedParams)
    .map(([key, value]) => `${key}=${value}`)
    .join('&');

  // Generate SHA-1 hash with api_secret
  return crypto
    .createHash('sha1')
    .update(queryString + process.env.CLOUDINARY_API_SECRET)
    .digest('hex');
}

// Helper function to create upload parameters
export function createUploadParams(
  publicId: string,
  folder: string,
  resourceType: 'image' | 'video' = 'image'
) {
  // Check if Cloudinary is properly configured
  if (missingVars.length > 0) {
    throw new Error('Cloudinary not configured. Please set all required environment variables.');
  }

  const timestamp = Math.round(new Date().getTime() / 1000);
  
  const params = {
    timestamp,
    folder,
    public_id: publicId,
    resource_type: resourceType,
    overwrite: true,
  };

  const signature = generateSignature(params);

  return {
    ...params,
    signature,
    api_key: process.env.CLOUDINARY_API_KEY,
    cloud_name: process.env.CLOUDINARY_CLOUD_NAME,
  };
}

// Cloudinary service class for media operations
export class CloudinaryService {
  /**
   * Generates a server-side signature for direct Cloudinary uploads.
   * @param filename Original filename for validation.
   * @param contentType MIME type for validation.
   * @param tripId Trip ID for folder organization.
   * @returns Signed upload parameters.
   */
  static async generateUploadSignature(
    filename: string, 
    contentType: string, 
    tripId: string
  ): Promise<{
    signature: string;
    timestamp: number;
    api_key: string;
    cloud_name: string;
    folder: string;
    public_id: string;
    resource_type: string;
  }> {
    // Generate unique public ID for the media
    const timestamp = Math.round(Date.now() / 1000);
    const publicId = `trav-flut/${tripId}/${timestamp}_${filename.replace(/\.[^/.]+$/, '')}`;
    const folder = `trav-flut/${tripId}`;
    
    // Determine resource type from content type
    const resourceType = contentType.startsWith('video/') ? 'video' : 'image';

    const params = {
      timestamp,
      public_id: publicId,
      folder,
      resource_type: 'auto', // Use 'auto' to match the URL path
      overwrite: true,
    };

    const signature = generateSignature(params);

    return {
      signature,
      timestamp,
      api_key: process.env.CLOUDINARY_API_KEY!,
      cloud_name: process.env.CLOUDINARY_CLOUD_NAME!,
      folder,
      public_id: publicId,
      resource_type: 'auto',
    };
  }

  /**
   * Validates Cloudinary response and creates a Media record in the database.
   * @param data Cloudinary response data + context.
   * @param userId ID of the user who uploaded the media.
   * @returns The created Media object.
   */
  static async confirmUpload(data: {
    url: string;
    secure_url: string;
    public_id: string;
    format: string;
    resource_type: string;
    bytes: number;
    original_filename: string;
    tripId?: string;
    threadEntryId?: string;
  }, userId: string): Promise<any> {
    // Basic validation of Cloudinary response
    if (!data.secure_url || !data.public_id || !data.resource_type || !data.bytes) {
      throw new Error('Invalid Cloudinary response data');
    }
    if (!data.secure_url.startsWith(`https://res.cloudinary.com/${process.env.CLOUDINARY_CLOUD_NAME}/`)) {
      throw new Error('Invalid Cloudinary URL origin');
    }

    // Import prisma here to avoid circular dependencies
    const { prisma } = await import('./db');

    // Create Media record in DB
    const media = await prisma.media.create({
      data: {
        url: data.secure_url,
        publicId: data.public_id,
        type: data.resource_type.toUpperCase() === 'IMAGE' ? 'IMAGE' : 'VIDEO',
        filename: data.original_filename,
        size: data.bytes,
        uploadedById: userId,
        tripId: data.tripId,
      },
    });

    // Link to TripThreadEntry if provided
    if (data.threadEntryId) {
      await prisma.tripThreadEntry.update({
        where: { id: data.threadEntryId },
        data: { 
          mediaId: media.id, 
          mediaUrl: media.url // Update both for transition
        },
      });
    }

    return media;
  }

  // Optional: Method to delete media from Cloudinary and DB
  static async deleteMedia(publicId: string): Promise<void> {
    try {
      await cloudinary.uploader.destroy(publicId);
      const { prisma } = await import('./db');
      await prisma.media.deleteMany({ where: { publicId } });
    } catch (error) {
      console.error('Error deleting media:', error);
      throw error;
    }
  }
}
