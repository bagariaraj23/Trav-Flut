import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { ApiResponse } from '@/types/api'

// Publish final post
export async function POST(
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

    // Publish final post
    await prisma.tripFinalPost.update({
      where: { tripId },
      data: {
        isPublished: true
      }
    })

    return NextResponse.json<ApiResponse>({
      success: true,
      message: 'Final post published successfully'
    })

  } catch (error: any) {
    console.error('Publish final post error:', error)
    
    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}