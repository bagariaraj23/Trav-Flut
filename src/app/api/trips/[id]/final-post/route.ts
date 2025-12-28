import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { updateFinalPostSchema } from '@/lib/validation'
import { ApiResponse, TripFinalPostResponse } from '@/types/api'

// Get final post preview
export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const tripId = id
    
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

    // Check if trip exists and user is owner
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        finalPost: true
      }
    })

    if (!trip) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Trip not found'
      }, { status: 404 })
    }

    if (trip.userId !== userId) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Only trip owner can view final post'
      }, { status: 403 })
    }

    if (!trip.finalPost) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Final post not generated yet. Please end the trip first.'
      }, { status: 404 })
    }

    const finalPostResponse: TripFinalPostResponse = {
      ...trip.finalPost,
      createdAt: trip.finalPost.createdAt.toISOString()
    }

    return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
      success: true,
      data: finalPostResponse
    })

  } catch (error: any) {
    console.error('Get final post error:', error)
    
    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}

// Update final post
export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const tripId = id
    
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
    const validatedData = updateFinalPostSchema.parse(body)

    // Check if trip exists and user is owner
    const trip = await prisma.trip.findUnique({
      where: { id: tripId },
      include: {
        finalPost: true
      }
    })

    if (!trip) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Trip not found'
      }, { status: 404 })
    }

    if (trip.userId !== userId) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Only trip owner can update final post'
      }, { status: 403 })
    }

    if (!trip.finalPost) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Final post not found'
      }, { status: 404 })
    }

    // Update final post
    const updatedFinalPost = await prisma.tripFinalPost.update({
      where: { tripId },
      data: validatedData
    })

    const finalPostResponse: TripFinalPostResponse = {
      ...updatedFinalPost,
      createdAt: updatedFinalPost.createdAt.toISOString()
    }

    return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
      success: true,
      data: finalPostResponse
    })

  } catch (error: any) {
    console.error('Update final post error:', error)
    
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