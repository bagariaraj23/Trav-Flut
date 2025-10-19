import { NextRequest } from "next/server";
import { requestReset } from "@/lib/services/passwordReset";
import { prisma } from "@/lib/prisma";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));
    const debugEcho =
      process.env.NODE_ENV !== "production" &&
      (process.env.PASSWORD_RESET_DEBUG_ECHO === "1" ||
        req.headers.get("x-debug-echo") === "1");

    // Check if Prisma client is initialized
    if (!prisma) {
      console.error("Prisma client is not initialized");
      return Response.json(
        { error: "Internal server error" },
        { status: 500 }
      );
    }

    let leakedToken: string | undefined;
    await requestReset(
      body,
      { ip: req.headers.get("x-forwarded-for") || undefined, userAgent: req.headers.get("user-agent") || undefined },
      debugEcho ? { onToken: (t) => (leakedToken = t) } : undefined,
    );

    return Response.json({
      ok: true,
      message: "If an account exists for this email, a reset link has been sent.",
      ...(debugEcho ? { debugToken: leakedToken } : {}),
    });
  } catch (error) {
    console.error("Password reset error:", error);
    return Response.json(
      { error: "Failed to process password reset request" },
      { status: 500 }
    );
  }
}