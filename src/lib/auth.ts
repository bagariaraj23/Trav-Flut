import jwt from 'jsonwebtoken'
import bcrypt from 'bcryptjs'
import { prisma } from './prisma'
import { User } from '@prisma/client'

const JWT_SECRET = process.env.JWT_SECRET || 'fallback-secret'
const JWT_REFRESH_SECRET = process.env.JWT_REFRESH_SECRET || 'fallback-refresh-secret'

export interface JWTPayload {
  userId: string
  email: string
  iat?: number
  exp?: number
}

export class AuthService {
  // Generate access token (24 hours)
  static generateAccessToken(user: User): string {
    return jwt.sign(
      { userId: user.id, email: user.email },
      JWT_SECRET,
      { expiresIn: '24h' }
    )
  }

  // Generate refresh token (30 days)
  static generateRefreshToken(user: User): string {
    return jwt.sign(
      { userId: user.id, email: user.email },
      JWT_REFRESH_SECRET,
      { expiresIn: '30d' }
    )
  }

  // Verify access token
  static verifyAccessToken(token: string): JWTPayload | null {
    try {
      return jwt.verify(token, JWT_SECRET) as JWTPayload
    } catch (error) {
      return null
    }
  }

  // Verify refresh token
  static verifyRefreshToken(token: string): JWTPayload | null {
    try {
      return jwt.verify(token, JWT_REFRESH_SECRET) as JWTPayload
    } catch (error) {
      return null
    }
  }

  // Hash password
  static async hashPassword(password: string): Promise<string> {
    return bcrypt.hash(password, 12)
  }

  // Compare password
  static async comparePassword(password: string, hashedPassword: string): Promise<boolean> {
    return bcrypt.compare(password, hashedPassword)
  }

  // Store refresh token in database
  static async storeRefreshToken(userId: string, refreshToken: string): Promise<void> {
    const expiresAt = new Date()
    expiresAt.setDate(expiresAt.getDate() + 30) // 30 days

    await prisma.jWTRefreshToken.create({
      data: {
        userId,
        refreshToken,
        expiresAt
      }
    })
  }

  // Validate refresh token from database
  static async validateRefreshToken(refreshToken: string): Promise<User | null> {
    const tokenRecord = await prisma.jWTRefreshToken.findUnique({
      where: { refreshToken },
      include: { user: true }
    })

    if (!tokenRecord || tokenRecord.expiresAt < new Date()) {
      // Clean up expired token
      if (tokenRecord) {
        await prisma.jWTRefreshToken.delete({
          where: { id: tokenRecord.id }
        })
      }
      return null
    }

    return tokenRecord.user
  }

  // Revoke refresh token
  static async revokeRefreshToken(refreshToken: string): Promise<void> {
    await prisma.jWTRefreshToken.deleteMany({
      where: { refreshToken }
    })
  }

  // Clean expired tokens
  static async cleanExpiredTokens(): Promise<void> {
    await prisma.jWTRefreshToken.deleteMany({
      where: {
        expiresAt: {
          lt: new Date()
        }
      }
    })
  }
}