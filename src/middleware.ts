import { NextResponse } from 'next/server'
import type { NextRequest } from 'next/server'

export function middleware(request: NextRequest) {
    // Always return the request as-is
    return NextResponse.next()
}

// Configure which paths the middleware runs on
export const config = {
    // Only run on API routes
    matcher: '/api/:path*',
}