import { NextRequest, NextResponse } from "next/server";
import { AuthService } from "@/lib/auth";
import { withLogging, withRateLimit } from "@/lib/middleware";
import { sendSupportEmail } from "@/lib/services/email";
import { SUPPORT_EMAIL, parseSupportBody } from "@/lib/supportMessage";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "support", async (rateLimitedReq) => {
      const body = await rateLimitedReq.json().catch(() => ({}));
      const parsed = parseSupportBody(body);
      if (!parsed.ok) {
        return NextResponse.json({ error: parsed.error }, { status: 400 });
      }
      if (parsed.honeypot) {
        return NextResponse.json({ ok: true });
      }

      let email = parsed.email;
      let name = parsed.name;
      let userId: string | null = null;
      const authHeader = rateLimitedReq.headers.get("authorization");
      if (authHeader?.startsWith("Bearer ")) {
        const payload = AuthService.verifyAccessToken(authHeader.slice(7));
        if (payload?.email) {
          email = payload.email;
          userId = payload.userId;
        }
      }

      if (!email) {
        return NextResponse.json(
          { error: "Enter an email so we can reply." },
          { status: 400 }
        );
      }

      const sent = await sendSupportEmail({
        to: SUPPORT_EMAIL,
        fromEmail: email,
        fromName: name || null,
        userId,
        message: parsed.message,
      });

      if (!sent) {
        return NextResponse.json(
          { error: "We could not send that just now. Email us directly instead." },
          { status: 503 }
        );
      }

      return NextResponse.json({
        ok: true,
        message: "Sent. We will reply by email.",
      });
    });
  });

  return loggedHandler(request);
}
