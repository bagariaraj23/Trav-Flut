import { NextRequest } from 'next/server'
import { ok, badRequest, serverError, unauthorized } from '@/lib/response-helpers'
import { prisma } from '@/lib/db'
import { z } from 'zod'
import { CloudinaryService } from '@/lib/cloudinary'

// Validation schema for signature request
const signatureSchema = z.object({
  tripId: z.string().uuid(),
  resourceType: z.enum(['image', 'video']).default('image'),
  filename: z.string().min(1).max(255)
})

export async function POST(request: NextRequest) {
  try {
    console.log('[MEDIA] Received signature request')
    
    const body = await request.json()
    console.log('[MEDIA] Request body:', body)
    
    const validatedData = signatureSchema.parse(body)
    const { tripId, resourceType, filename } = validatedData
    console.log('[MEDIA] Validated data:', { tripId, resourceType, filename })

    // TODO: Add authentication middleware
    // For now, we'll use a placeholder user ID
    const userId = 'temp-user-id'

    // Verify trip exists and user has access
    const trip = await prisma.trip.findFirst({
      where: {
        id: tripId,
        OR: [
          { userId }, // User owns the trip
          { 
            participants: {
              some: { userId } // User is a participant
            }
          }
        ]
      }
    })

    if (!trip) {
      return badRequest('Trip not found or access denied')
    }

    // Generate upload signature
    const contentType = resourceType === 'image' ? 'image/jpeg' : 'video/mp4'
    const uploadParams = await CloudinaryService.generateUploadSignature(
      filename,
      contentType,
      tripId
    )

    console.log(`[MEDIA] Generated signed upload params for trip ${tripId}, user ${userId}`)

    return ok({
      uploadParams,
      publicId: uploadParams.public_id,
      folder: uploadParams.folder,
      resourceType,
      message: 'Signed upload parameters generated successfully'
    })

  } catch (error: any) {
    console.error('[MEDIA] Error in signature endpoint:', error)
    
    if (error.name === 'ZodError') {
      return badRequest('Invalid request data', error.errors)
    }
    
    return serverError('Failed to generate upload signature')
  }
}
