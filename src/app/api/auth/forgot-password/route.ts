import { NextRequest } from "next/server";
import { requestReset } from "@/lib/services/passwordReset";
// import { ok } from "@/lib/response";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  const debugEcho =
    process.env.NODE_ENV !== "production" &&
    (process.env.PASSWORD_RESET_DEBUG_ECHO === "1" ||
     req.headers.get("x-debug-echo") === "1");

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
}