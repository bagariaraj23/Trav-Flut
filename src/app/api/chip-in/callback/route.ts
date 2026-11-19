import { NextRequest, NextResponse } from "next/server";
import { withLogging } from "@/lib/middleware";
import { recordPaidChipIn } from "@/lib/services/chipInPayment";

function asText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.trim().slice(0, max);
}

async function readCallback(request: NextRequest): Promise<{
  orderId: string;
  paymentId: string;
  signature: string;
}> {
  const contentType = request.headers.get("content-type") || "";
  if (contentType.includes("application/json")) {
    const body = (await request.json().catch(() => ({}))) as Record<string, unknown>;
    return {
      orderId: asText(body.razorpay_order_id ?? body.orderId, 80),
      paymentId: asText(body.razorpay_payment_id ?? body.paymentId, 80),
      signature: asText(body.razorpay_signature ?? body.signature, 200),
    };
  }
  if (request.method === "GET") {
    return {
      orderId: asText(request.nextUrl.searchParams.get("razorpay_order_id"), 80),
      paymentId: asText(request.nextUrl.searchParams.get("razorpay_payment_id"), 80),
      signature: asText(request.nextUrl.searchParams.get("razorpay_signature"), 200),
    };
  }
  const form = await request.formData().catch(() => null);
  const field = (name: string) => {
    const value = form?.get(name);
    return asText(typeof value === "string" ? value : "", name === "razorpay_signature" ? 200 : 80);
  };
  return {
    orderId: field("razorpay_order_id"),
    paymentId: field("razorpay_payment_id"),
    signature: field("razorpay_signature"),
  };
}

function thanksRedirect(request: NextRequest, paid: boolean) {
  const url = new URL("/thanks", request.nextUrl.origin);
  if (!paid) url.searchParams.set("problem", "1");
  return NextResponse.redirect(url, 303);
}

async function finish(request: NextRequest) {
  const payment = await readCallback(request);
  const paid = await recordPaidChipIn(payment.orderId, payment.paymentId, payment.signature);
  return thanksRedirect(request, paid);
}

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => finish(req));
  return loggedHandler(request);
}

export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => finish(req));
  return loggedHandler(request);
}
