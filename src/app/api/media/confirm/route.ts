import { NextRequest } from 'next/server'
import { ok, badRequest, serverError, unauthorized } from '@/lib/response-helpers'
import { prisma } from '@/lib/db'
import { z } from 'zod'
import { CloudinaryService } from '@/lib/cloudinary'

// Validation schema for media confirmation
const confirmSchema = z.object({
  url: z.string().url(),
  secure_url: z.string().url(),
  public_id: z.string(),
  format: z.string(),
  resource_type: z.string(),
  bytes: z.number().positive(),
  original_filename: z.string(),
  tripId: z.string().uuid().optional(),
  threadEntryId: z.string().uuid().optional(),
})

export async function POST(request: NextRequest) {
  try {
    console.log('[MEDIA] Received confirmation request')
    
    const body = await request.json()
    console.log('[MEDIA] Request body:', body)
    
    const validatedData = confirmSchema.parse(body)
    console.log('[MEDIA] Validated data:', validatedData)

    // TODO: Add authentication middleware
    // For now, we'll use a placeholder user ID
    const userId = 'temp-user-id'

    // Verify trip access if tripId is provided
    if (validatedData.tripId) {
      const trip = await prisma.trip.findFirst({
        where: {
          id: validatedData.tripId,
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
    }

    // Verify thread entry access if threadEntryId is provided
    if (validatedData.threadEntryId) {
      const threadEntry = await prisma.tripThreadEntry.findFirst({
        where: {
          id: validatedData.threadEntryId,
          OR: [
            { authorId: userId }, // User is the author
            {
              trip: {
                OR: [
                  { userId }, // User owns the trip
                  { 
                    participants: {
                      some: { userId } // User is a participant
                    }
                  }
                ]
              }
            }
          ]
        }
      })

      if (!threadEntry) {
        return badRequest('Thread entry not found or access denied')
      }
    }

    // Confirm upload and create media record
    const media = await CloudinaryService.confirmUpload(validatedData, userId)

    console.log(`[MEDIA] Media confirmed and created: ${media.id}`)

    return ok({
      media,
      message: 'Media upload confirmed successfully'
    })

  } catch (error: any) {
    console.error('[MEDIA] Error in confirmation endpoint:', error)
    
    if (error.name === 'ZodError') {
      return badRequest('Invalid request data', error.errors)
    }
    
    return serverError('Failed to confirm media upload')
  }
}
