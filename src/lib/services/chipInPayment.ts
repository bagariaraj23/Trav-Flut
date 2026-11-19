import { prisma } from "@/lib/prisma";
import { capturedRazorpayPayment, verifyRazorpaySignature } from "@/lib/services/razorpay";

export async function recordPaidChipIn(
  orderId: string,
  paymentId: string,
  signature: string
): Promise<boolean> {
  if (!verifyRazorpaySignature(orderId, paymentId, signature)) return false;
  const chipIn = await prisma.chipIn.findUnique({ where: { providerOrderId: orderId } });
  if (!chipIn) return false;
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
  return true;
}

export async function syncCapturedChipIn(orderId: string): Promise<"paid" | "pending" | "missing"> {
  if (!/^order_[A-Za-z0-9]{8,32}$/.test(orderId)) return "missing";
  const chipIn = await prisma.chipIn.findUnique({ where: { providerOrderId: orderId } });
  if (!chipIn) return "missing";
  if (chipIn.status === "PAID") return "paid";
  const paymentId = await capturedRazorpayPayment(orderId);
  if (!paymentId) return "pending";
  await prisma.chipIn.update({
    where: { id: chipIn.id },
    data: {
      status: "PAID",
      providerPaymentId: paymentId,
      paidAt: chipIn.paidAt ?? new Date(),
    },
  });
  return "paid";
}
