import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { createTripSchema } from '@/lib/validation'
import { ApiResponse, TripResponse } from '@/types/api'
import { TextUtils } from '@/lib/text-utils'

// Create a new trip
export async function POST(request: NextRequest) {
  try {
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
    const validatedData = createTripSchema.parse(body)

    // Check if user has an ongoing trip
    const ongoingTrip = await prisma.trip.findFirst({
      where: {
        userId,
        status: 'ONGOING'
      }
    })

    if (ongoingTrip) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'You already have an ongoing trip. Please end it before starting a new one.'
      }, { status: 409 })
    }

    // Format text data before creating trip
    const formattedData = {
      ...validatedData,
      title: TextUtils.formatTripTitle(validatedData.title),
      description: validatedData.description ? TextUtils.formatContent(validatedData.description) : validatedData.description,
      destinations: TextUtils.formatDestinations(validatedData.destinations),
    };

    // Create trip
    const trip = await prisma.trip.create({
      data: {
        ...formattedData,
        userId,
        startDate: formattedData.startDate ? new Date(formattedData.startDate) : null,
        endDate: formattedData.endDate ? new Date(formattedData.endDate) : null,
        status: 'ONGOING'
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
        },
        _count: {
          select: {
            threadEntries: true,
            media: true,
            participants: true
          }
        }
      }
    })

    const tripResponse: TripResponse = {
      ...trip,
      startDate: trip.startDate?.toISOString() || undefined,
      endDate: trip.endDate?.toISOString() || undefined,
      createdAt: trip.createdAt.toISOString(),
      updatedAt: trip.updatedAt.toISOString(),
      user: trip.user ? {
        ...trip.user,
        createdAt: trip.user.createdAt.toISOString(),
        updatedAt: trip.user.updatedAt.toISOString()
      } : undefined
    }

    return NextResponse.json<ApiResponse<TripResponse>>({
      success: true,
      data: tripResponse
    }, { status: 201 })

  } catch (error: any) {
    console.error('Create trip error:', error)
    
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

// Get user's trips
export async function GET(request: NextRequest) {
  try {
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
    const { searchParams } = new URL(request.url)
    const status = searchParams.get('status') as 'UPCOMING' | 'ONGOING' | 'ENDED' | null

    const whereClause: any = { userId }
    if (status) {
      whereClause.status = status
    }

    const trips = await prisma.trip.findMany({
      where: whereClause,
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
        },
        _count: {
          select: {
            threadEntries: true,
            media: true,
            participants: true
          }
        }
      },
      orderBy: { createdAt: 'desc' }
    })

    const tripsResponse: TripResponse[] = trips.map(trip => ({
      ...trip,
      startDate: trip.startDate?.toISOString() || undefined,
      endDate: trip.endDate?.toISOString() || undefined,
      createdAt: trip.createdAt.toISOString(),
      updatedAt: trip.updatedAt.toISOString(),
      user: trip.user ? {
        ...trip.user,
        createdAt: trip.user.createdAt.toISOString(),
        updatedAt: trip.user.updatedAt.toISOString()
      } : undefined
    }))

    return NextResponse.json<ApiResponse<TripResponse[]>>({
      success: true,
      data: tripsResponse
    })

  } catch (error: any) {
    console.error('Get trips error:', error)
    
    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}