import { beforeEach, describe, expect, it, vi } from "vitest";

const updateMany = vi.hoisted(() => vi.fn());
const findUnique = vi.hoisted(() => vi.fn());
const verifyRazorpaySignature = vi.hoisted(() => vi.fn());
const capturedRazorpayPayment = vi.hoisted(() => vi.fn());

vi.mock("../../src/lib/prisma", () => ({
  prisma: {
    chipIn: {
      updateMany,
      findUnique,
    },
  },
}));

vi.mock("../../src/lib/services/razorpay", () => ({
  verifyRazorpaySignature,
  capturedRazorpayPayment,
}));

import { recordPaidChipIn, syncCapturedChipIn } from "../../src/lib/services/chipInPayment";

const orderId = "order_Abcd1234WXYZ";
const row = { id: "chip-1", status: "CREATED", providerOrderId: orderId };

describe("chip-in payment claim", () => {
  beforeEach(() => {
    updateMany.mockReset();
    findUnique.mockReset();
    verifyRazorpaySignature.mockReset();
    capturedRazorpayPayment.mockReset();
    verifyRazorpaySignature.mockReturnValue(true);
    capturedRazorpayPayment.mockResolvedValue("pay_123");
    findUnique.mockResolvedValue(row);
    updateMany.mockResolvedValue({ count: 1 });
  });

  it("refuses a signature that does not match and does not write", async () => {
    verifyRazorpaySignature.mockReturnValue(false);

    await expect(recordPaidChipIn(orderId, "pay_123", "nope")).resolves.toBe(false);
    expect(updateMany).not.toHaveBeenCalled();
  });

  it("claims an unpaid row once", async () => {
    await expect(recordPaidChipIn(orderId, "pay_123", "sig")).resolves.toBe(true);

    expect(updateMany).toHaveBeenCalledWith({
      where: { providerOrderId: orderId, status: { not: "PAID" } },
      data: expect.objectContaining({
        status: "PAID",
        providerPaymentId: "pay_123",
      }),
    });
    expect(findUnique).not.toHaveBeenCalled();
  });

  it("treats a row the other writer already marked paid as paid", async () => {
    updateMany.mockResolvedValue({ count: 0 });
    findUnique.mockResolvedValue({ status: "PAID" });

    await expect(recordPaidChipIn(orderId, "pay_123", "sig")).resolves.toBe(true);
    expect(updateMany).toHaveBeenCalledTimes(1);
  });

  it("leaves the row unpaid when the payment id is already stored elsewhere", async () => {
    updateMany.mockRejectedValue({ code: "P2002" });
    findUnique.mockResolvedValueOnce(row).mockResolvedValueOnce({ status: "CREATED" });

    await expect(syncCapturedChipIn(orderId)).resolves.toBe("pending");
  });

  it("does not ask Razorpay again after the row is paid", async () => {
    findUnique.mockResolvedValue({ ...row, status: "PAID" });

    await expect(syncCapturedChipIn(orderId)).resolves.toBe("paid");
    expect(capturedRazorpayPayment).not.toHaveBeenCalled();
    expect(updateMany).not.toHaveBeenCalled();
  });

  it("stays pending until Razorpay has captured the payment", async () => {
    capturedRazorpayPayment.mockResolvedValue(null);

    await expect(syncCapturedChipIn(orderId)).resolves.toBe("pending");
    expect(updateMany).not.toHaveBeenCalled();
  });

  it("ignores an order id that cannot be a Razorpay order", async () => {
    await expect(syncCapturedChipIn("not-an-order")).resolves.toBe("missing");
    expect(findUnique).not.toHaveBeenCalled();
  });
});
