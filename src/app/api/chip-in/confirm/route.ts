import { NextRequest, NextResponse } from "next/server";
import { withLogging, withRateLimit } from "@/lib/middleware";
import { prisma } from "@/lib/prisma";
import { verifyRazorpaySignature } from "@/lib/services/razorpay";

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
      if (!verifyRazorpaySignature(orderId, paymentId, signature)) {
        return NextResponse.json({ error: "That payment could not be confirmed." }, { status: 400 });
      }

      const chipIn = await prisma.chipIn.findUnique({ where: { providerOrderId: orderId } });
      if (!chipIn) {
        return NextResponse.json({ error: "That payment could not be confirmed." }, { status: 400 });
      }
      if (chipIn.status !== "PAID") {
        await prisma.chipIn.update({
          where: { id: chipIn.id },
          data: {
            status: "PAID",
            providerPaymentId: paymentId,
            paidAt: new Date(),
          },
        });
      }
      return NextResponse.json({ ok: true });
    });
  });
  return loggedHandler(request);
}
