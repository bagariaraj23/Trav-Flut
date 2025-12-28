import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { ApiResponse, UserProfile } from '@/types/api'

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params;
    const userId = id
    
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

    if (!payload || payload.userId !== userId) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'Unauthorized'
      }, { status: 403 })
    }

    // Get current privacy setting
    const currentUser = await prisma.user.findUnique({
      where: { id: userId },
      select: { isPrivate: true }
    })

    if (!currentUser) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'User not found'
      }, { status: 404 })
    }

    // Toggle privacy
    const updatedUser = await prisma.user.update({
      where: { id: userId },
      data: {
        isPrivate: !currentUser.isPrivate,
        updatedAt: new Date()
      },
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
    })

    const userProfile: UserProfile = {
      ...updatedUser,
      username: updatedUser.username ?? undefined,
      name: updatedUser.name ?? undefined,
      avatarUrl: updatedUser.avatarUrl ?? undefined,
      bio: updatedUser.bio ?? undefined,
      createdAt: updatedUser.createdAt.toISOString(),
      updatedAt: updatedUser.updatedAt.toISOString()
    }

    return NextResponse.json<ApiResponse<UserProfile>>({
      success: true,
      data: userProfile
    })

  } catch (error: any) {
    console.error('Toggle privacy error:', error)
    
    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}