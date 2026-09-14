export class AppError extends Error {
  public readonly statusCode: number
  public readonly isOperational: boolean

  constructor(message: string, statusCode: number, isOperational = true) {
    super(message)
    this.statusCode = statusCode
    this.isOperational = isOperational

    Error.captureStackTrace(this, this.constructor)
  }
}

export class ValidationError extends AppError {
  constructor(message: string) {
    super(message, 400)
  }
}

export class AuthenticationError extends AppError {
  constructor(message: string = 'Authentication required') {
    super(message, 401)
  }
}

export class AuthorizationError extends AppError {
  constructor(message: string = 'Access denied') {
    super(message, 403)
  }
}

export class NotFoundError extends AppError {
  constructor(message: string = 'Resource not found') {
    super(message, 404)
  }
}

export class ConflictError extends AppError {
  constructor(message: string) {
    super(message, 409)
  }
}

export class UnsettledBalanceError extends ConflictError {
  readonly netMinor: number
  readonly code = "UNSETTLED_BALANCE" as const

  constructor(netMinor: number, message = "Settle your trip balance before leaving or deleting your account") {
    super(message)
    this.netMinor = netMinor
  }
}

export class RateLimitError extends AppError {
  constructor(message: string = 'Too many requests') {
    super(message, 429)
  }
}

export class DatabaseError extends AppError {
  constructor(message: string = 'Database operation failed') {
    super(message, 500, false)
  }
}

export class ExternalServiceError extends AppError {
  constructor(message: string = 'External service unavailable') {
    super(message, 503, false)
  }
}

// Error handler utility
export function handleError(error: unknown): AppError {
  if (error instanceof AppError) {
    return error
  }

  if (error instanceof Error) {
    // Log unexpected errors
    console.error('Unexpected error:', error)
    return new AppError('Internal server error', 500, false)
  }

  console.error('Unknown error:', error)
  return new AppError('Internal server error', 500, false)
}