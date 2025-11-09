import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

export function middleware(request: NextRequest) {
  const { pathname, searchParams } = request.nextUrl;

  // Protect password reset routes - require valid token and email
  if (pathname === "/reset-success" || pathname === "/forgot-password") {
    const token = searchParams.get("t");
    const email = searchParams.get("email");

    console.log(
      `[Middleware] ${pathname} - token: ${
        token ? "present" : "missing"
      }, email: ${email ? "present" : "missing"}`
    );

    // If no token or email, redirect to home with error
    if (!token || !email) {
      console.log(
        `[Middleware] Redirecting ${pathname} - missing token or email`
      );
      const redirectUrl = new URL("/", request.url);
      redirectUrl.searchParams.set("error", "invalid-reset-link");
      redirectUrl.searchParams.set(
        "message",
        "This password reset link is invalid. Please request a new one."
      );
      return NextResponse.redirect(redirectUrl);
    }

    // Additional validation: check if token and email look valid
    // Note: email might be URL encoded, so decode it first
    const decodedEmail = decodeURIComponent(email);
    if (token.length < 16 || !decodedEmail.includes("@")) {
      console.log(
        `[Middleware] Redirecting ${pathname} - invalid token or email format`
      );
      const redirectUrl = new URL("/", request.url);
      redirectUrl.searchParams.set("error", "invalid-reset-link");
      redirectUrl.searchParams.set(
        "message",
        "This password reset link is invalid. Please request a new one."
      );
      return NextResponse.redirect(redirectUrl);
    }

    console.log(`[Middleware] Allowing ${pathname} - token and email valid`);
  }

  // Always return the request as-is for other routes
  return NextResponse.next();
}

// Configure which paths the middleware runs on
export const config = {
  // Run on API routes and password reset pages
  matcher: ["/api/:path*", "/reset-success", "/forgot-password"],
};
