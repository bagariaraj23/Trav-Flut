import { NextRequest, NextResponse } from "next/server";
import { withLogging, withRateLimit } from "@/lib/middleware";
import { recordPaidChipIn } from "@/lib/services/chipInPayment";

function asText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, max);
}

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "chip_in", async (rateLimitedReq) => {
      const body = await rateLimitedReq.json().catch(() => ({}));
      const record =
        body && typeof body === "object" ? (body as Record<string, unknown>) : {};
      const orderId = asText(record.orderId, 80);
      const paymentId = asText(record.paymentId, 80);
      const signature = asText(record.signature, 200);
      const paid = await recordPaidChipIn(orderId, paymentId, signature);
      if (!paid) {
        return NextResponse.json({ error: "That payment could not be confirmed." }, { status: 400 });
      }
      return NextResponse.json({ ok: true });
    });
  });
  return loggedHandler(request);
}
