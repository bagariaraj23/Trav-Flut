import { prisma } from "@/lib/prisma";
import { verifyRazorpaySignature } from "@/lib/services/razorpay";

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
