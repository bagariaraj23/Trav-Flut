import { NextRequest, NextResponse } from "next/server";
import { requestReset } from "@/lib/services/passwordReset";
import { prisma } from "@/lib/prisma";
import { withRateLimit, withLogging } from "@/lib/middleware";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "auth_forgot", async (rateLimitedReq) => {
      try {
        const body = await rateLimitedReq.json().catch(() => ({}));
        const debugEcho =
          process.env.NODE_ENV !== "production" &&
          (process.env.PASSWORD_RESET_DEBUG_ECHO === "1" ||
            rateLimitedReq.headers.get("x-debug-echo") === "1");

        // Check if Prisma client is initialized
        if (!prisma) {
          console.error("Prisma client is not initialized");
          return NextResponse.json(
            { error: "Internal server error" },
            { status: 500 }
          );
        }

        let leakedToken: string | undefined;
        await requestReset(
          body,
          {
            ip: rateLimitedReq.headers.get("x-forwarded-for") || undefined,
            userAgent: rateLimitedReq.headers.get("user-agent") || undefined,
          },
          debugEcho ? { onToken: (t) => (leakedToken = t) } : undefined
        );

        return NextResponse.json({
          ok: true,
          message:
            "If an account exists for this email, a reset link has been sent.",
          ...(debugEcho ? { debugToken: leakedToken } : {}),
        });
      } catch (error) {
        console.error("Password reset error:", error);
        return NextResponse.json(
          { error: "Failed to process password reset request" },
          { status: 500 }
        );
      }
    });
  });

  return await loggedHandler(request);
}
