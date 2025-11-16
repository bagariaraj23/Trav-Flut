import { NextResponse } from 'next/server'

export function ok(data: any, message?: string) {
  return NextResponse.json({
    success: true,
    message: message || 'Success',
    data,
  })
}

export function badRequest(message: string, errors?: any) {
  return NextResponse.json({
    success: false,
    message,
    errors,
  }, { status: 400 })
}

export function unauthorized(message: string = 'Unauthorized') {
  return NextResponse.json({
    success: false,
    message,
  }, { status: 401 })
}

export function forbidden(message: string = 'Forbidden') {
  return NextResponse.json({
    success: false,
    message,
  }, { status: 403 })
}

export function notFound(message: string = 'Not found') {
  return NextResponse.json({
    success: false,
    message,
  }, { status: 404 })
}

export function conflict(message: string) {
  return NextResponse.json({
    success: false,
    message,
  }, { status: 409 })
}

export function serverError(message: string = 'Internal server error') {
  return NextResponse.json({
    success: false,
    message,
  }, { status: 500 })
}

export function rateLimitExceeded(message: string = 'Too many requests') {
  return NextResponse.json({
    success: false,
    message,
  }, { status: 429 })
}
