import { createHmac } from "crypto";

export function razorpayConfig(): { keyId: string; keySecret: string } | null {
  const keyId = process.env.RAZORPAY_KEY_ID?.trim();
  const keySecret = process.env.RAZORPAY_KEY_SECRET?.trim();
  if (!keyId || !keySecret) return null;
  return { keyId, keySecret };
}

export async function createRazorpayOrder(amountMinor: number, receipt: string): Promise<
  | { ok: true; orderId: string; keyId: string }
  | { ok: false; reason: "unconfigured" | "failed" }
> {
  const config = razorpayConfig();
  if (!config) return { ok: false, reason: "unconfigured" };

  const auth = Buffer.from(`${config.keyId}:${config.keySecret}`).toString("base64");
  try {
    const response = await fetch("https://api.razorpay.com/v1/orders", {
      method: "POST",
      headers: {
        Authorization: `Basic ${auth}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: amountMinor,
        currency: "INR",
        receipt: receipt.slice(0, 40),
      }),
    });
    if (!response.ok) return { ok: false, reason: "failed" };
    const data = (await response.json()) as { id?: string };
    if (!data.id) return { ok: false, reason: "failed" };
    return { ok: true, orderId: data.id, keyId: config.keyId };
  } catch {
    return { ok: false, reason: "failed" };
  }
}

export function verifyRazorpaySignature(orderId: string, paymentId: string, signature: string): boolean {
  const config = razorpayConfig();
  if (!config || !orderId || !paymentId || !signature) return false;
  const expected = createHmac("sha256", config.keySecret)
    .update(`${orderId}|${paymentId}`)
    .digest("hex");
  return expected === signature;
}
