import { NextRequest, NextResponse } from "next/server";
import { withLogging, withRateLimit } from "@/lib/middleware";
import { prisma } from "@/lib/prisma";
import { CHIP_IN_CURRENCY, parseChipInAmount, parseChipInName } from "@/lib/chipIn";
import { createRazorpayOrder } from "@/lib/services/razorpay";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "chip_in", async (rateLimitedReq) => {
      const body = await rateLimitedReq.json().catch(() => ({}));
      const parsed = parseChipInAmount(body);
      if (!parsed.ok) {
        return NextResponse.json({ error: parsed.error }, { status: 400 });
      }

      const chipIn = await prisma.chipIn.create({
        data: {
          amountMinor: parsed.amountMinor,
          currency: CHIP_IN_CURRENCY,
          displayName: parseChipInName(body),
        },
      });

      const order = await createRazorpayOrder(parsed.amountMinor, chipIn.id);
      if (!order.ok) {
        await prisma.chipIn.update({
          where: { id: chipIn.id },
          data: { status: "FAILED" },
        });
        if (order.reason === "unauthorized") {
          return NextResponse.json({ error: "Razorpay did not accept these keys." }, { status: 401 });
        }
        const status = order.reason === "unconfigured" ? 503 : 500;
        const message =
          order.reason === "unconfigured"
            ? "Chip-in isn't open on this server yet."
            : "The payment window didn't open. Try again in a moment.";
        return NextResponse.json({ error: message }, { status });
      }

      await prisma.chipIn.update({
        where: { id: chipIn.id },
        data: { providerOrderId: order.orderId },
      });

      return NextResponse.json({
        ok: true,
        orderId: order.orderId,
        keyId: order.keyId,
        amountMinor: parsed.amountMinor,
        currency: CHIP_IN_CURRENCY,
        name: "TripThread",
        description: "Chip in",
      });
    });
  });
  return loggedHandler(request);
}
