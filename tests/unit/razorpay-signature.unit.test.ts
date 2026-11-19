import { createHmac } from "crypto";
import { afterEach, describe, expect, it } from "vitest";
import { verifyRazorpaySignature } from "../../src/lib/services/razorpay";

const ORIGINAL_ID = process.env.RAZORPAY_KEY_ID;
const ORIGINAL_SECRET = process.env.RAZORPAY_KEY_SECRET;

afterEach(() => {
  if (ORIGINAL_ID === undefined) delete process.env.RAZORPAY_KEY_ID;
  else process.env.RAZORPAY_KEY_ID = ORIGINAL_ID;
  if (ORIGINAL_SECRET === undefined) delete process.env.RAZORPAY_KEY_SECRET;
  else process.env.RAZORPAY_KEY_SECRET = ORIGINAL_SECRET;
});

describe("verifyRazorpaySignature", () => {
  it("accepts the HMAC of order id and payment id and rejects anything else", () => {
    process.env.RAZORPAY_KEY_ID = "rzp_test_example";
    process.env.RAZORPAY_KEY_SECRET = "test-secret";
    const signature = createHmac("sha256", "test-secret").update("order_1|pay_1").digest("hex");
    expect(verifyRazorpaySignature("order_1", "pay_1", signature)).toBe(true);
    expect(verifyRazorpaySignature("order_1", "pay_1", "not-the-signature")).toBe(false);
    expect(verifyRazorpaySignature("", "pay_1", signature)).toBe(false);
  });
});
