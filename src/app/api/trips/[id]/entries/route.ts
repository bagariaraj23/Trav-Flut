import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { createThreadEntrySchema } from '@/lib/validation'
import { ApiResponse, TripThreadEntryResponse } from '@/types/api'
import { TextUtils } from '@/lib/text-utils'

// Create a new thread entry
export async function POST(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const tripId = params.id
    
    // Verify authentication
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Authorization token required'
      }, { status: 401 })
    }

    const token = authHeader.substring(7)
    const payload = AuthService.verifyAccessToken(token)

    if (!payload) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Invalid token'
      }, { status: 401 })
    }

    const userId = payload.userId
    const body = await request.json()
    
    // Validate input
    const validatedData = createThreadEntrySchema.parse(body)

    // Check if trip exists and user has access
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        participants: true
      }
    })

    if (!trip) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Trip not found'
      }, { status: 404 })
    }

    // Check if user is owner or participant
    const isOwner = trip.userId === userId
    const isParticipant = trip.participants.some(p => p.userId === userId)

    if (!isOwner && !isParticipant) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Access denied. You must be the trip owner or a participant.'
      }, { status: 403 })
    }

    if (trip.status !== 'ONGOING') {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Cannot add entries to a trip that is not ongoing'
      }, { status: 400 })
    }

    // Format text data before creating thread entry
    const formattedData = {
      ...validatedData,
      contentText: validatedData.contentText ? TextUtils.formatContent(validatedData.contentText) : validatedData.contentText,
      locationName: validatedData.locationName ? TextUtils.formatLocation(validatedData.locationName) : validatedData.locationName,
    };

    // Create thread entry
    const threadEntry = await prisma.tripThreadEntry.create({
      data: {
        tripId,
        authorId: userId,
        type: formattedData.type,
        contentText: formattedData.contentText,
        mediaUrl: formattedData.mediaUrl,
        locationName: formattedData.locationName,
        gpsCoordinates: formattedData.gpsCoordinates
      },
      include: {
        author: {
          select: {
            id: true,
            email: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
            isPrivate: true,
            createdAt: true,
            updatedAt: true
          }
        },
        media: true
      }
    })

    // Add tags if provided
    if (validatedData.taggedUserIds && validatedData.taggedUserIds.length > 0) {
      await prisma.tripThreadTag.createMany({
        data: validatedData.taggedUserIds.map(taggedUserId => ({
          threadEntryId: threadEntry.id,
          taggedUserId
        })),
        skipDuplicates: true
      })
    }

    // Fetch the complete entry with tags
    const completeEntry = await prisma.tripThreadEntry.findUnique({
      where: { id: threadEntry.id },
      include: {
        author: {
          select: {
            id: true,
            email: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
            isPrivate: true,
            createdAt: true,
            updatedAt: true
          }
        },
        taggedUsers: {
          include: {
            taggedUser: {
              select: {
                id: true,
                email: true,
                username: true,
                name: true,
                avatarUrl: true,
                bio: true,
                isPrivate: true,
                createdAt: true,
                updatedAt: true
              }
            }
          }
        },
        media: true
      }
    })

    const entryResponse: TripThreadEntryResponse = {
      ...completeEntry!,
      createdAt: completeEntry!.createdAt.toISOString(),
      author: {
        ...completeEntry!.author,
        createdAt: completeEntry!.author.createdAt.toISOString(),
        updatedAt: completeEntry!.author.updatedAt.toISOString()
      },
      taggedUsers: completeEntry!.taggedUsers.map(tag => ({
        ...tag.taggedUser,
        createdAt: tag.taggedUser.createdAt.toISOString(),
        updatedAt: tag.taggedUser.updatedAt.toISOString()
      })),
      media: completeEntry!.media ? {
        ...completeEntry!.media,
        createdAt: completeEntry!.media.createdAt.toISOString()
      } : undefined
    }

    return NextResponse.json<ApiResponse<TripThreadEntryResponse>>({
      success: true,
      data: entryResponse
    }, { status: 201 })

  } catch (error: any) {
    console.error('Create thread entry error:', error)
    
    if (error.name === 'ZodError') {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: error.errors[0]?.message || 'Validation error'
      }, { status: 400 })
    }

    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}

// Get trip thread entries
export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const tripId = params.id
    
    // Verify authentication
    const authHeader = request.headers.get('authorization')
    if (!authHeader?.startsWith('Bearer ')) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Authorization token required'
      }, { status: 401 })
    }

    const token = authHeader.substring(7)
    const payload = AuthService.verifyAccessToken(token)

    if (!payload) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Invalid token'
      }, { status: 401 })
    }

    const userId = payload.userId

    // Check if trip exists and user has access
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        participants: true,
        user: {
          select: { isPrivate: true }
        }
      }
    })

    if (!trip) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Trip not found'
      }, { status: 404 })
    }

    // Check access permissions
    const isOwner = trip.userId === userId
    const isParticipant = trip.participants.some(p => p.userId === userId)
    
    if (!isOwner && !isParticipant) {
      // Check if trip owner's profile is public or if current user follows them
      if (trip.user?.isPrivate) {
        const followRelation = await prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: userId,
              followeeId: trip.userId
            }
          }
        })

        if (!followRelation) {
          return NextResponse.json<ApiResponse>({
            success: false,
            error: 'Access denied to this private trip'
          }, { status: 403 })
        }
      }
    }

    // Get thread entries
    const entries = await prisma.tripThreadEntry.findMany({
      where: { tripId },
      include: {
        author: {
          select: {
            id: true,
            email: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
            isPrivate: true,
            createdAt: true,
            updatedAt: true
          }
        },
        taggedUsers: {
          include: {
            taggedUser: {
              select: {
                id: true,
                email: true,
                username: true,
                name: true,
                avatarUrl: true,
                bio: true,
                isPrivate: true,
                createdAt: true,
                updatedAt: true
              }
            }
          }
        },
        media: true
      },
      orderBy: { createdAt: 'asc' }
    })

    const entriesResponse: TripThreadEntryResponse[] = entries.map(entry => ({
      ...entry,
      createdAt: entry.createdAt.toISOString(),
      author: {
        ...entry.author,
        createdAt: entry.author.createdAt.toISOString(),
        updatedAt: entry.author.updatedAt.toISOString()
      },
      taggedUsers: entry.taggedUsers.map(tag => ({
        ...tag.taggedUser,
        createdAt: tag.taggedUser.createdAt.toISOString(),
        updatedAt: tag.taggedUser.updatedAt.toISOString()
      })),
      media: entry.media ? {
        ...entry.media,
        createdAt: entry.media.createdAt.toISOString()
      } : undefined
    }))

    return NextResponse.json<ApiResponse<TripThreadEntryResponse[]>>({
      success: true,
      data: entriesResponse
    })

  } catch (error: any) {
    console.error('Get thread entries error:', error)
    
    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}