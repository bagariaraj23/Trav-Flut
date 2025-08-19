import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { addParticipantSchema } from '@/lib/validation'
import { ApiResponse, TripParticipantResponse } from '@/types/api'

// Add participant to trip
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

    const currentUserId = payload.userId
    const body = await request.json()
    
    // Validate input
    const validatedData = addParticipantSchema.parse(body)

    // Check if trip exists and user is owner
    const trip = await prisma.trip.findUnique({
      where: { id: tripId }
    })

    if (!trip) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Trip not found'
      }, { status: 404 })
    }

    if (trip.userId !== currentUserId) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Only trip owner can add participants'
      }, { status: 403 })
    }

    // Check if user to be added exists
    const userToAdd = await prisma.user.findUnique({
      where: { id: validatedData.userId }
    })

    if (!userToAdd) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'User not found'
      }, { status: 404 })
    }

    // Check if user is already a participant
    const existingParticipant = await prisma.tripParticipant.findUnique({
      where: {
        tripId_userId: {
          tripId,
          userId: validatedData.userId
        }
      }
    })

    if (existingParticipant) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'User is already a participant'
      }, { status: 400 })
    }

    // Add participant
    const participant = await prisma.tripParticipant.create({
      data: {
        tripId,
        userId: validatedData.userId,
        role: validatedData.role || 'member'
      },
      include: {
        user: {
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
    })

    const participantResponse: TripParticipantResponse = {
      ...participant,
      joinedAt: participant.joinedAt.toISOString(),
      user: {
        ...participant.user,
        username: participant.user.username ?? undefined, 
        name: participant.user.name ?? undefined,
        avatarUrl: participant.user.avatarUrl ?? undefined,
        bio: participant.user.bio ?? undefined,
        createdAt: participant.user.createdAt.toISOString(),
        updatedAt: participant.user.updatedAt.toISOString()
      }
    }

    return NextResponse.json<ApiResponse<TripParticipantResponse>>({
      success: true,
      data: participantResponse
    }, { status: 201 })

  } catch (error: any) {
    console.error('Add participant error:', error)
    
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

// Get trip participants
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

    // Get participants
    const participants = await prisma.tripParticipant.findMany({
      where: { tripId },
      include: {
        user: {
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
      },
      orderBy: { joinedAt: 'asc' }
    })

    const participantsResponse: TripParticipantResponse[] = participants.map(participant => ({
      ...participant,
      joinedAt: participant.joinedAt.toISOString(),
      user: {
        ...participant.user,
        username: participant.user.username ?? undefined,
        name: participant.user.name ?? undefined,
        avatarUrl: participant.user.avatarUrl ?? undefined,
        bio: participant.user.bio ?? undefined,
        createdAt: participant.user.createdAt.toISOString(),
        updatedAt: participant.user.updatedAt.toISOString()
      }
    }))

    return NextResponse.json<ApiResponse<TripParticipantResponse[]>>({
      success: true,
      data: participantsResponse
    })

  } catch (error: any) {
    console.error('Get participants error:', error)
    
    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}