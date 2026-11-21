import { createHmac } from "crypto";
import type { ChipInCurrency } from "@/lib/chipIn";

export function razorpayConfig(): { keyId: string; keySecret: string } | null {
  const keyId = process.env.RAZORPAY_KEY_ID?.trim();
  const keySecret = process.env.RAZORPAY_KEY_SECRET?.trim();
  if (!keyId || !keySecret) return null;
  return { keyId, keySecret };
}

export function razorpayOrderFailure(
  status: number,
  description: string
): "unauthorized" | "currency" | "failed" {
  if (status === 401) return "unauthorized";
  const text = description.toLowerCase();
  if (text.includes("currency") || text.includes("international")) return "currency";
  return "failed";
}

export async function createRazorpayOrder(
  amountMinor: number,
  receipt: string,
  currency: ChipInCurrency = "INR"
): Promise<
  | { ok: true; orderId: string; keyId: string }
  | { ok: false; reason: "unconfigured" | "unauthorized" | "currency" | "failed" }
> {
  const config = razorpayConfig();
  if (!config) return { ok: false, reason: "unconfigured" };
  if (!Number.isInteger(amountMinor) || amountMinor < 100) return { ok: false, reason: "failed" };

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
        currency,
        receipt: receipt.slice(0, 40),
      }),
    });
    if (!response.ok) {
      const data = (await response.json().catch(() => ({}))) as {
        error?: { description?: string };
      };
      return {
        ok: false,
        reason: razorpayOrderFailure(response.status, data.error?.description ?? ""),
      };
    }
    const data = (await response.json()) as { id?: string };
    if (!data.id) return { ok: false, reason: "failed" };
    return { ok: true, orderId: data.id, keyId: config.keyId };
  } catch {
    return { ok: false, reason: "failed" };
  }
}

export async function capturedRazorpayPayment(orderId: string): Promise<string | null> {
  const config = razorpayConfig();
  if (!config || !/^order_[A-Za-z0-9]{8,32}$/.test(orderId)) return null;
  const auth = Buffer.from(`${config.keyId}:${config.keySecret}`).toString("base64");
  try {
    const response = await fetch(`https://api.razorpay.com/v1/orders/${orderId}/payments`, {
      headers: { Authorization: `Basic ${auth}` },
    });
    if (!response.ok) return null;
    const data = (await response.json()) as { items?: { id?: string; status?: string }[] };
    const captured = data.items?.find((item) => item.status === "captured" && item.id);
    return captured?.id ?? null;
  } catch {
    return null;
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
