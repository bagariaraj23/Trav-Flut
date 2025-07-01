import { NextRequest, NextResponse } from 'next/server'
import { prisma } from '@/lib/prisma'
import { AuthService } from '@/lib/auth'
import { signupSchema } from '@/lib/validation'
import { ApiResponse, AuthResponse } from '@/types/api'

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    
    // Validate input
    const validatedData = signupSchema.parse(body)
    const { email, password, name, username } = validatedData

    // Check if user already exists
    const existingUser = await prisma.user.findUnique({
      where: { email: email.toLowerCase() }
    })

    if (existingUser) {
      return NextResponse.json<ApiResponse>({
        success: false,
        error: 'User with this email already exists'
      }, { status: 400 })
    }

    // Check username uniqueness if provided
    if (username) {
      const existingUsername = await prisma.user.findUnique({
        where: { username }
      })

      if (existingUsername) {
        return NextResponse.json<ApiResponse>({
          success: false,
          error: 'Username is already taken'
        }, { status: 400 })
      }
    }

    // Hash password
    const hashedPassword = await AuthService.hashPassword(password)

    // Create user
    const user = await prisma.user.create({
      data: {
        email: email.toLowerCase(),
        password: hashedPassword,
        name,
        username
      }
    })

    // Generate tokens
    const accessToken = AuthService.generateAccessToken(user)
    const refreshToken = AuthService.generateRefreshToken(user)

    // Store refresh token
    await AuthService.storeRefreshToken(user.id, refreshToken)

    // Remove password from response
    const { password: _, ...userWithoutPassword } = user

    const response: ApiResponse<AuthResponse> = {
      success: true,
      data: {
        user: {
          ...userWithoutPassword,
          createdAt: user.createdAt.toISOString(),
          updatedAt: user.updatedAt.toISOString()
        },
        accessToken,
        refreshToken
      }
    }

    return NextResponse.json(response, { status: 201 })

  } catch (error: any) {
    console.error('Signup error:', error)
    
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