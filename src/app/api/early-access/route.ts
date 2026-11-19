import { NextRequest, NextResponse } from "next/server";
import { withLogging, withRateLimit } from "@/lib/middleware";
import { prisma } from "@/lib/prisma";
import {
  EARLY_ACCESS_TARGET,
  earlyAccessProgress,
  parseEarlyAccessBody,
} from "@/lib/earlyAccess";
import { sendEarlyAccessEmail } from "@/lib/services/email";
import { addAndroidTester } from "@/lib/services/firebaseAppDistribution";

function clientIp(request: NextRequest): string | null {
  return (
    request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    request.headers.get("x-real-ip") ||
    null
  );
}

export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "early_access_read", async () => {
      const count = await prisma.earlyAccessRequest.count();
      return NextResponse.json(earlyAccessProgress(count, EARLY_ACCESS_TARGET));
    });
  });
  return loggedHandler(request);
}

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "early_access", async (rateLimitedReq) => {
      const body = await rateLimitedReq.json().catch(() => ({}));
      const parsed = parseEarlyAccessBody(body);
      if (!parsed.ok) {
        return NextResponse.json({ error: parsed.error }, { status: 400 });
      }
      if (parsed.honeypot) {
        const count = await prisma.earlyAccessRequest.count();
        return NextResponse.json({
          ok: true,
          ...earlyAccessProgress(count, EARLY_ACCESS_TARGET),
        });
      }

      let created = true;
      try {
        await prisma.earlyAccessRequest.create({
          data: {
            email: parsed.email,
            name: parsed.name,
            platform: parsed.platform,
            createdIp: clientIp(rateLimitedReq),
          },
        });
      } catch (error) {
        const code =
          error && typeof error === "object" && "code" in error
            ? (error as { code?: string }).code
            : undefined;
        if (code === "P2002") {
          created = false;
        } else {
          throw error;
        }
      }

      let emailed = false;
      if (created) {
        const firebaseInvited =
          parsed.platform === "ANDROID"
            ? (await addAndroidTester(parsed.email)) === "added"
            : false;
        emailed = await sendEarlyAccessEmail({
          to: parsed.email,
          name: parsed.name,
          platform: parsed.platform,
          downloadUrl: process.env.FIREBASE_ANDROID_DOWNLOAD_URL,
          firebaseInvited,
        });
      }

      const count = await prisma.earlyAccessRequest.count();
      return NextResponse.json({
        ok: true,
        created,
        emailed,
        platform: parsed.platform,
        ...earlyAccessProgress(count, EARLY_ACCESS_TARGET),
      });
    });
  });
  return loggedHandler(request);
}
