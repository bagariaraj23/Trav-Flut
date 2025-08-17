import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { updateProfileSchema } from '@/lib/validation'
import { ApiResponse, UserProfile, UserStats } from '@/types/api'
import { TextUtils } from '@/lib/text-utils'

// Get user profile
export async function GET(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const userId = params.id
    
    // Get current user from token (optional)
    const authHeader = request.headers.get('authorization')
    let currentUserId: string | null = null
    
    if (authHeader?.startsWith('Bearer ')) {
      const token = authHeader.substring(7)
      const payload = AuthService.verifyAccessToken(token)
      currentUserId = payload?.userId || null
    }

    // Find user
    const user = await prisma.user.findUnique({
      where: { id: userId },
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

    if (!user) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'User not found'
      }, { status: 404 })
    }

    // Check privacy settings
    if (user.isPrivate && currentUserId !== userId) {
      // Check if current user follows this user
      if (currentUserId) {
        const followRelation = await prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: currentUserId,
              followeeId: userId
            }
          }
        })

        if (!followRelation) {
          // Return limited profile for private users
          const limitedProfile: UserProfile = {
            id: user.id,
            email: '',
            username: user.username,
            name: user.name,
            avatarUrl: user.avatarUrl,
            bio: undefined,
            isPrivate: user.isPrivate,
            createdAt: user.createdAt.toISOString(),
            updatedAt: user.updatedAt.toISOString()
          }

          return NextResponse.json<ApiResponse<UserProfile>>({
            success: true,
            data: limitedProfile
          })
        }
      } else {
        return NextResponse.json<ApiResponse>({
          success: false,
          error: 'This profile is private'
        }, { status: 403 })
      }
    }

    const userProfile: UserProfile = {
      ...user,
      createdAt: user.createdAt.toISOString(),
      updatedAt: user.updatedAt.toISOString()
    }

    return NextResponse.json<ApiResponse<UserProfile>>({
      success: true,
      data: userProfile
    })

  } catch (error: any) {
    console.error('Get user error:', error)
    
    return NextResponse.json<ApiResponse>({
      success: false,
      error: 'Internal server error'
    }, { status: 500 })
  }
}

// Update user profile
export async function PUT(
  request: NextRequest,
  { params }: { params: { id: string } }
) {
  try {
    const userId = params.id
    
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

    const body = await request.json()
    
    // Validate input
    const validatedData = updateProfileSchema.parse(body)

    // Check username uniqueness if provided
    if (validatedData.username) {
      const existingUser = await prisma.user.findUnique({
        where: { username: validatedData.username }
      })

      if (existingUser && existingUser.id !== userId) {
        return NextResponse.json<ApiResponse>({
          success: false,
          error: 'Username is already taken'
        }, { status: 400 })
      }
    }

    // Format text data before updating
    const formattedData = {
      ...validatedData,
      name: validatedData.name ? TextUtils.formatName(validatedData.name) : validatedData.name,
      bio: validatedData.bio ? TextUtils.formatBio(validatedData.bio) : validatedData.bio,
      username: validatedData.username ? TextUtils.formatUsername(validatedData.username) : validatedData.username,
    };

    // Update user
    const updatedUser = await prisma.user.update({
      where: { id: userId },
      data: {
        ...formattedData,
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
      createdAt: updatedUser.createdAt.toISOString(),
      updatedAt: updatedUser.updatedAt.toISOString()
    }

    return NextResponse.json<ApiResponse<UserProfile>>({
      success: true,
      data: userProfile
    })

  } catch (error: any) {
    console.error('Update user error:', error)
    
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