import { NextRequest, NextResponse } from 'next/server'
import { AuthService } from '@/lib/auth'
import { prisma } from '@/lib/prisma'
import { ApiResponse, TripFinalPostResponse } from '@/types/api'
import { TripFinalizerService } from '@/lib/services/tripFinalizer'
import { handleError } from '@/lib/errors'

// Publish final post
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
        error: 'Only trip owner can publish final post'
      }, { status: 403 })
    }

    if (!trip.finalPost) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Final post not found'
      }, { status: 404 })
    }

    if (trip.finalPost.isPublished) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Final post is already published'
      }, { status: 400 })
    }

    const published = await TripFinalizerService.publishFinalPost(tripId, userId)
    const response: TripFinalPostResponse = {
      ...published,
      caption: published.caption ?? undefined,
      coverMediaUrl: published.coverMediaUrl ?? undefined,
      publishedAt: published.publishedAt ? published.publishedAt.toISOString() : undefined,
      createdAt: published.createdAt.toISOString(),
      updatedAt: published.updatedAt.toISOString(),
      generationStatus: published.generationStatus
    }

    return NextResponse.json<ApiResponse<TripFinalPostResponse>>({
      success: true,
      data: response,
      message: 'Final post published successfully'
    })

  } catch (error: any) {
    const appError = handleError(error)

    return NextResponse.json<ApiResponse>({
      success: false,
      error: appError.message
    }, { status: appError.statusCode })
  }
}