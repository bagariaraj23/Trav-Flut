import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { ApiResponse, UserProfile } from '@/types/api'
import { withAuth, AuthenticatedRequest, handleApiError } from '@/lib/middleware'
import { AuthService } from '@/lib/auth'

async function handler(
  request: AuthenticatedRequest,
  { params }: { params: { id: string } }
) {
  try {
    const targetUserId = params.id
    const currentUserId = request.user!.userId
    const { searchParams } = new URL(request.url)
    const page = parseInt(searchParams.get('page') || '1')
    const limit = parseInt(searchParams.get('limit') || '20')
    const offset = (page - 1) * limit

    // Get target user's privacy status
    const targetUser = await prisma.user.findUnique({
      where: { id: targetUserId },
      select: { id: true, isPrivate: true },
    })

    if (!targetUser) {
      return NextResponse.json<ApiResponse>(
        {
          success: false,
          error: 'User not found',
        },
        { status: 404 }
      )
    }

    // Privacy check: For private accounts, only show if:
    // 1. Current user is viewing their own profile, OR
    // 2. Current user is following the target user AND target user is following back (mutual follow)
    if (targetUser.isPrivate && targetUserId !== currentUserId) {
      const [userFollowsTarget, targetFollowsUser] = await Promise.all([
        prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: currentUserId,
              followeeId: targetUserId,
            },
          },
        }),
        prisma.follow.findUnique({
          where: {
            followerId_followeeId: {
              followerId: targetUserId,
              followeeId: currentUserId,
            },
          },
        }),
      ])

      // Must have mutual follow (both following each other)
      if (!userFollowsTarget || !targetFollowsUser) {
        return NextResponse.json<ApiResponse>(
          {
            success: false,
            error: 'Access denied. This is a private account. You must follow each other to view following list.',
          },
          { status: 403 }
        )
      }
    }

    // Get following
    const follows = await prisma.follow.findMany({
      where: { followerId: targetUserId },
      include: {
        followee: {
          select: {
            id: true,
            email: true,
            username: true,
            name: true,
            avatarUrl: true,
            bio: true,
            isPrivate: true,
            createdAt: true,
            updatedAt: true,
          },
        },
      },
      skip: offset,
      take: limit,
      orderBy: { createdAt: 'desc' },
    })

    // Get total count
    const totalCount = await prisma.follow.count({
      where: { followerId: targetUserId },
    })

    const following: UserProfile[] = follows.map((follow) => ({
      ...follow.followee,
      createdAt: follow.followee.createdAt.toISOString(),
      updatedAt: follow.followee.updatedAt.toISOString(),
    }))

    return NextResponse.json<
      ApiResponse<{
        following: UserProfile[]
        pagination: {
          page: number
          limit: number
          total: number
          totalPages: number
        }
      }>
    >({
      success: true,
      data: {
        following,
        pagination: {
          page,
          limit,
          total: totalCount,
          totalPages: Math.ceil(totalCount / limit),
        },
      },
    })
  } catch (error: any) {
    console.error('Get following error:', error)
    return handleApiError(error)
  }
}

export async function GET(
  request: NextRequest,
  context: { params: { id: string } }
) {
  return withAuth(request, (authRequest) => handler(authRequest, context))
}