import { prisma } from "@/lib/prisma";
import { capturedRazorpayPayment, verifyRazorpaySignature } from "@/lib/services/razorpay";

function isUniqueConflict(error: unknown): boolean {
  return Boolean(
    error &&
      typeof error === "object" &&
      "code" in error &&
      (error as { code?: string }).code === "P2002"
  );
}

/**
 * One conditional update, keyed by the Razorpay order. Postgres locks the
 * matching row, so confirm and the callback cannot both change it. The second
 * writer matches zero rows once the first has set PAID. providerPaymentId is
 * unique, so a payment id already stored on another row is rejected.
 */
async function claimPaidChipIn(orderId: string, paymentId: string): Promise<boolean> {
  try {
    const claimed = await prisma.chipIn.updateMany({
      where: { providerOrderId: orderId, status: { not: "PAID" } },
      data: {
        status: "PAID",
        providerPaymentId: paymentId,
        paidAt: new Date(),
      },
    });
    if (claimed.count > 0) return true;
  } catch (error) {
    if (!isUniqueConflict(error)) throw error;
  }

  const current = await prisma.chipIn.findUnique({
    where: { providerOrderId: orderId },
    select: { status: true },
  });
  return current?.status === "PAID";
}

export async function recordPaidChipIn(
  orderId: string,
  paymentId: string,
  signature: string
): Promise<boolean> {
  if (!verifyRazorpaySignature(orderId, paymentId, signature)) return false;
  return claimPaidChipIn(orderId, paymentId);
}

export async function syncCapturedChipIn(orderId: string): Promise<"paid" | "pending" | "missing"> {
  if (!/^order_[A-Za-z0-9]{8,32}$/.test(orderId)) return "missing";
  const chipIn = await prisma.chipIn.findUnique({ where: { providerOrderId: orderId } });
  if (!chipIn) return "missing";
  if (chipIn.status === "PAID") return "paid";
  const paymentId = await capturedRazorpayPayment(orderId);
  if (!paymentId) return "pending";
  const paid = await claimPaidChipIn(orderId, paymentId);
  return paid ? "paid" : "pending";
}
