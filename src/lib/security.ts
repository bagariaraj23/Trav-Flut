import crypto from 'crypto'
import { NextRequest } from 'next/server'
import { rateLimit as redisRateLimit } from "./rateLimit"; // Legacy function for backward compatibility

// Input sanitization
export function sanitizeInput(input: string): string {
  return input
    .trim()
    .replace(/[<>]/g, '') // Remove potential HTML tags
    .replace(/javascript:/gi, '') // Remove javascript: protocol
    .replace(/on\w+=/gi, '') // Remove event handlers
}

// SQL injection prevention (additional layer beyond Prisma)
export function validateSqlInput(input: string): boolean {
  const sqlInjectionPattern = /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|UNION|SCRIPT)\b)|(-{2})|(\*\/)|(\*)|(\bOR\b.*=.*)|(\bAND\b.*=.*)/i
  return !sqlInjectionPattern.test(input)
}

// XSS prevention
export function escapeHtml(unsafe: string): string {
  return unsafe
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;')
}

// CSRF token generation and validation
export function generateCSRFToken(): string {
  return crypto.randomBytes(32).toString('hex')
}

export function validateCSRFToken(token: string, sessionToken: string): boolean {
  return crypto.timingSafeEqual(
    Buffer.from(token, 'hex'),
    Buffer.from(sessionToken, 'hex')
  )
}

// Secure random string generation
export function generateSecureToken(length: number = 32): string {
  return crypto.randomBytes(length).toString('hex')
}

// Password strength validation
export function validatePasswordStrength(password: string): {
  isValid: boolean
  score: number
  feedback: string[]
} {
  const feedback: string[] = []
  let score = 0

  // Length check
  if (password.length >= 8) score += 1
  else feedback.push('Password should be at least 8 characters long')

  if (password.length >= 12) score += 1

  // Character variety checks
  if (/[a-z]/.test(password)) score += 1
  else feedback.push('Include lowercase letters')

  if (/[A-Z]/.test(password)) score += 1
  else feedback.push('Include uppercase letters')

  if (/\d/.test(password)) score += 1
  else feedback.push('Include numbers')

  if (/[!@#$%^&*(),.?":{}|<>]/.test(password)) score += 1
  else feedback.push('Include special characters')

  // Common password check
  const commonPasswords = ['password', '123456', 'qwerty', 'abc123', 'password123']
  if (commonPasswords.includes(password.toLowerCase())) {
    score = 0
    feedback.push('Avoid common passwords')
  }

  return {
    isValid: score >= 4,
    score,
    feedback
  }
}

// File upload security
export function validateFileUpload(file: {
  name: string
  type: string
  size: number
}): { isValid: boolean; errors: string[] } {
  const errors: string[] = []

  // File size limits (50MB)
  const maxSize = 50 * 1024 * 1024
  if (file.size > maxSize) {
    errors.push('File size exceeds 50MB limit')
  }

  // Allowed file types
  const allowedTypes = [
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'video/mp4',
    'video/mov',
    'video/avi'
  ]

  if (!allowedTypes.includes(file.type)) {
    errors.push('File type not allowed')
  }

  // File name validation
  const fileNamePattern = /^[a-zA-Z0-9._-]+$/
  if (!fileNamePattern.test(file.name)) {
    errors.push('Invalid file name format')
  }

  // Check for multiple file extensions at the END of filename
  // This allows dots in the filename (e.g., "my.file.name.jpg" is valid)
  // But rejects suspicious double extensions (e.g., "image.jpg.exe")
  const parts = file.name.split('.')
  if (parts.length >= 3) {
    const lastExt = parts[parts.length - 1].toLowerCase()
    const secondLastExt = parts[parts.length - 2].toLowerCase()
    
    // Known safe double extensions (allowed)
    const safeDoubleExtensions = ['tar.gz', 'tar.bz2', 'tar.xz']
    const isSafeDoubleExt = safeDoubleExtensions.includes(`${secondLastExt}.${lastExt}`)
    
    // Reject if it looks like a malicious double extension (e.g., .jpg.exe, .png.bat)
    // Only check if the last extension is suspicious
    const suspiciousExtensions = ['exe', 'bat', 'cmd', 'com', 'scr', 'vbs', 'js', 'jar', 'sh', 'dll']
    if (!isSafeDoubleExt && suspiciousExtensions.includes(lastExt)) {
      errors.push('Multiple file extensions not allowed')
    }
  }

  return {
    isValid: errors.length === 0,
    errors
  }
}

// IP address validation and rate limiting helpers
export function getClientIP(request: NextRequest): string {
  const forwarded = request.headers.get('x-forwarded-for')
  const realIP = request.headers.get('x-real-ip')

  if (forwarded) {
    return forwarded.split(',')[0].trim()
  }

  if (realIP) {
    return realIP
  }

  return request.headers.get("x-forwarded-for") || request.headers.get("x-real-ip") || 'unknown'
}

// Rate limiting configuration
interface RateLimitConfig {
  maxRequests: number
  windowMs: number
}

const rateLimits = {
  authenticated: {
    maxRequests: 1000,  // 1000 requests
    windowMs: 60 * 1000 // per minute
  },
  anonymous: {
    maxRequests: 60,    // 60 requests
    windowMs: 60 * 1000 // per minute
  }
}

interface RateLimitInfo {
  remaining: number
  reset: number
  isBlocked: boolean
}

// In-memory store for rate limiting
const rateLimit = new Map<string, { count: number; start: number }>()

// Generate a unique client identifier using multiple signals
export function getClientIdentifier(request: NextRequest, userId?: string): string {
  const signals = [
    getClientIP(request),
    request.headers.get('user-agent') || 'unknown',
    request.headers.get('sec-ch-ua') || '',      // Browser info
    request.headers.get('accept-language') || '', // Language preference
    userId || 'anon'                             // User ID if authenticated
  ]

  return crypto
    .createHash('sha256')
    .update(signals.join('|'))
    .digest('hex')
}

// Check rate limit for a client
export function checkRateLimit(
  identifier: string,
  isAuthenticated: boolean = false
): RateLimitInfo {
  const config = isAuthenticated ? rateLimits.authenticated : rateLimits.anonymous
  const now = Date.now()

  // Clean up expired entries
  Array.from(rateLimit.entries()).forEach(([key, data]) => {
    if (now - data.start > config.windowMs) {
      rateLimit.delete(key)
    }
  })

  const clientData = rateLimit.get(identifier) || { count: 0, start: now }

  // Reset window if expired
  if (now - clientData.start > config.windowMs) {
    clientData.count = 0
    clientData.start = now
  }

  // Increment counter
  clientData.count++
  rateLimit.set(identifier, clientData)

  const remaining = Math.max(0, config.maxRequests - clientData.count)
  const reset = clientData.start + config.windowMs

  return {
    remaining,
    reset,
    isBlocked: clientData.count > config.maxRequests
  }
}

// Headers for rate limit response
export function getRateLimitHeaders(info: RateLimitInfo): HeadersInit {
  return {
    'X-RateLimit-Remaining': info.remaining.toString(),
    'X-RateLimit-Reset': new Date(info.reset).toUTCString(),
    'X-RateLimit-Blocked': info.isBlocked.toString()
  }
}

// Enhanced rate limiting with user context
export interface RateLimitResult {
  allowed: boolean;
  remaining: number;
  resetAt: number;
  identifier: string;
}

export async function enforceRateLimit(
  request: NextRequest,
  userId?: string | null,
  scope: string = 'default'
): Promise<RateLimitResult> {
  // Get client identifier using multiple signals
  const identifier = getClientIdentifier(request, userId || undefined);
  const key = `${scope}:${identifier}`;

  const rl = await redisRateLimit(key, 100, 60);

  return {
    allowed: rl.allowed,
    remaining: rl.remaining,
    resetAt: rl.resetAt,
    identifier,
  };
}

// Secure headers configuration
export const securityHeaders = {
  'X-Content-Type-Options': 'nosniff',
  'X-Frame-Options': 'DENY',
  'X-XSS-Protection': '1; mode=block',
  'Referrer-Policy': 'strict-origin-when-cross-origin',
  'Permissions-Policy': 'camera=(), microphone=(), geolocation=(self)',
  'Strict-Transport-Security': 'max-age=31536000; includeSubDomains',
  'Content-Security-Policy': "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self' data:;"
}

// Environment validation
export function validateEnvironment(): void {
  const requiredEnvVars = [
    'DATABASE_URL',
    'JWT_SECRET',
    'JWT_REFRESH_SECRET',
    'NEXTAUTH_SECRET'
  ]

  const missing = requiredEnvVars.filter(envVar => !process.env[envVar])

  if (missing.length > 0) {
    throw new Error(`Missing required environment variables: ${missing.join(', ')}`)
  }

  // Validate JWT secrets strength
  if (process.env.JWT_SECRET && process.env.JWT_SECRET.length < 32) {
    throw new Error('JWT_SECRET must be at least 32 characters long')
  }

  if (process.env.JWT_REFRESH_SECRET && process.env.JWT_REFRESH_SECRET.length < 32) {
    throw new Error('JWT_REFRESH_SECRET must be at least 32 characters long')
  }
}

// Database connection security
export function validateDatabaseConnection(): void {
  const dbUrl = process.env.DATABASE_URL

  if (!dbUrl) {
    throw new Error('DATABASE_URL is required')
  }

  // Ensure SSL in production
  if (process.env.NODE_ENV === 'production' && !dbUrl.includes('sslmode=require')) {
    console.warn('Warning: Database connection should use SSL in production')
  }
}