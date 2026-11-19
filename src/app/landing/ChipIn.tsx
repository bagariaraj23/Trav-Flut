"use client";

import { useState } from "react";
import { CHIP_IN_MAX_RUPEES, CHIP_IN_MIN_RUPEES, CHIP_IN_PRESETS } from "@/lib/chipIn";

type RazorpayResponse = {
  razorpay_order_id: string;
  razorpay_payment_id: string;
  razorpay_signature: string;
};

type RazorpayInstance = {
  open: () => void;
  on: (event: "payment.failed", handler: (response: { error?: { description?: string } }) => void) => void;
};

type RazorpayCheckout = new (options: Record<string, unknown>) => RazorpayInstance;

declare global {
  interface Window {
    Razorpay?: RazorpayCheckout;
  }
}

function loadCheckout(): Promise<boolean> {
  if (window.Razorpay) return Promise.resolve(true);
  return new Promise((resolve) => {
    const script = document.createElement("script");
    script.src = "https://checkout.razorpay.com/v1/checkout.js";
    script.async = true;
    script.onload = () => resolve(Boolean(window.Razorpay));
    script.onerror = () => resolve(false);
    document.body.appendChild(script);
  });
}

export default function ChipIn() {
  const [selected, setSelected] = useState<number | "other">(100);
  const [custom, setCustom] = useState("");
  const [name, setName] = useState("");
  const [status, setStatus] = useState<"idle" | "opening" | "error">("idle");
  const [notice, setNotice] = useState("");

  const rupees = selected === "other" ? Number(custom) : selected;
  const amountReady = Number.isInteger(rupees) && rupees >= CHIP_IN_MIN_RUPEES && rupees <= CHIP_IN_MAX_RUPEES;

  async function chipIn() {
    if (!amountReady) {
      setStatus("error");
      setNotice(`Enter a whole amount from ₹${CHIP_IN_MIN_RUPEES} to ₹${CHIP_IN_MAX_RUPEES.toLocaleString("en-IN")}.`);
      return;
    }
    setStatus("opening");
    setNotice("");
    try {
      const ready = await loadCheckout();
      if (!ready || !window.Razorpay) {
        setStatus("error");
        setNotice("The payment window didn't load. Try again in a moment.");
        return;
      }
      const response = await fetch("/api/chip-in", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ amountRupees: rupees, name }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        setStatus("error");
        setNotice(typeof data.error === "string" ? data.error : "The payment window didn't open.");
        return;
      }
      let settled = false;
      const checkout = new window.Razorpay({
        key: data.keyId,
        amount: data.amountMinor,
        currency: data.currency,
        name: data.name,
        description: data.description,
        order_id: data.orderId,
        callback_url: `${window.location.origin}/api/chip-in/callback`,
        theme: { color: "#1D6FE8" },
        handler: async (payment: RazorpayResponse) => {
          settled = true;
          const confirm = await fetch("/api/chip-in/confirm", {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({
              orderId: payment.razorpay_order_id,
              paymentId: payment.razorpay_payment_id,
              signature: payment.razorpay_signature,
            }),
          });
          window.focus();
          window.location.assign(confirm.ok ? "/thanks" : "/thanks?problem=1");
        },
        modal: {
          ondismiss: () => {
            if (settled) return;
            setStatus("idle");
            setNotice("Payment cancelled.");
          },
        },
      });
      checkout.on("payment.failed", () => {
        settled = true;
        window.location.assign("/thanks?problem=1");
      });
      const orderId = data.orderId;
      const watch = window.setInterval(async () => {
        if (settled) {
          window.clearInterval(watch);
          return;
        }
        try {
          const statusResponse = await fetch(`/api/chip-in/status?orderId=${encodeURIComponent(orderId)}`);
          const statusBody = await statusResponse.json().catch(() => ({}));
          if (statusBody.status !== "paid" || settled) return;
          settled = true;
          window.clearInterval(watch);
          window.focus();
          window.location.assign("/thanks");
        } catch {
          // The next check asks again.
        }
      }, 1000);
      window.setTimeout(() => window.clearInterval(watch), 90000);
      checkout.open();
    } catch {
      setStatus("error");
      setNotice("The payment window didn't open.");
    }
  }

  return (
    <section id="chip-in" className="border-t border-ink/5 bg-cream" aria-labelledby="chip-in-heading">
      <div className="mx-auto flex max-w-6xl flex-col gap-6 px-5 py-10 sm:px-8 lg:flex-row lg:items-start lg:justify-between">
        <div className="max-w-md">
          <h2 id="chip-in-heading" className="font-display text-3xl tracking-tight">
            Chip in, if you like.
          </h2>
          <p className="mt-2 text-base leading-relaxed text-ink-soft">
            Any small amount. One step, UPI or card. No account.
          </p>
        </div>
        <div className="flex flex-col items-start gap-3">
          <div className="flex flex-wrap gap-2" role="group" aria-label="Amount">
            {CHIP_IN_PRESETS.map((amount) => (
              <button
                key={amount}
                type="button"
                onClick={() => {
                  setSelected(amount);
                  setNotice("");
                  setStatus("idle");
                }}
                className={`rounded-full px-4 py-2 text-sm font-medium ${
                  selected === amount ? "bg-ink text-cream" : "bg-white text-ink"
                }`}
                aria-pressed={selected === amount}
              >
                ₹{amount}
              </button>
            ))}
            <button
              type="button"
              onClick={() => {
                setSelected("other");
                setNotice("");
                setStatus("idle");
              }}
              className={`rounded-full px-4 py-2 text-sm font-medium ${
                selected === "other" ? "bg-ink text-cream" : "bg-white text-ink"
              }`}
              aria-pressed={selected === "other"}
            >
              Other
            </button>
          </div>
          <label className="text-sm font-medium">
            Your name
            <span className="ml-2 font-normal text-ink-soft">optional</span>
            <input
              className="mt-2 block w-56 rounded-2xl border border-ink/10 bg-white px-4 py-2 text-base outline-none focus:border-accent"
              value={name}
              maxLength={40}
              autoComplete="name"
              placeholder="Shown on the thank-you wall"
              onChange={(event) => setName(event.target.value.slice(0, 40))}
            />
          </label>
          {selected === "other" && (
            <label className="text-sm font-medium">
              Amount in rupees
              <input
                className="mt-2 w-36 rounded-2xl border border-ink/10 bg-white px-4 py-2 text-base outline-none focus:border-accent"
                inputMode="numeric"
                value={custom}
                autoFocus
                onChange={(event) => setCustom(event.target.value.replace(/[^\d]/g, "").slice(0, 5))}
              />
            </label>
          )}
          <button
            type="button"
            onClick={chipIn}
            disabled={status === "opening" || !amountReady}
            className="inline-flex items-center justify-center rounded-full bg-accent px-5 py-3 text-base font-medium text-white transition hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
          >
            {status === "opening" ? "Opening…" : amountReady ? `Chip in ₹${rupees}` : "Chip in"}
          </button>
          {notice && (
            <p className={`text-sm ${status === "error" ? "text-red-800" : "text-ink"}`} role="status">
              {notice}
            </p>
          )}
        </div>
      </div>
    </section>
  );
}
