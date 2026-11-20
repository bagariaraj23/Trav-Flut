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
 * One conditional update. Postgres locks the row, so a status poll and the
 * Razorpay callback cannot both change it. The second writer matches zero
 * rows once the first has set PAID. providerPaymentId is unique, so a payment
 * id already stored on another row is rejected instead of copied here.
 */
async function claimPaidChipIn(id: string, paymentId: string): Promise<boolean> {
  try {
    const claimed = await prisma.chipIn.updateMany({
      where: { id, status: { not: "PAID" } },
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
    where: { id },
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
  const chipIn = await prisma.chipIn.findUnique({ where: { providerOrderId: orderId } });
  if (!chipIn) return false;
  return claimPaidChipIn(chipIn.id, paymentId);
}

export async function syncCapturedChipIn(orderId: string): Promise<"paid" | "pending" | "missing"> {
  if (!/^order_[A-Za-z0-9]{8,32}$/.test(orderId)) return "missing";
  const chipIn = await prisma.chipIn.findUnique({ where: { providerOrderId: orderId } });
  if (!chipIn) return "missing";
  if (chipIn.status === "PAID") return "paid";
  const paymentId = await capturedRazorpayPayment(orderId);
  if (!paymentId) return "pending";
  const paid = await claimPaidChipIn(chipIn.id, paymentId);
  return paid ? "paid" : "pending";
}
