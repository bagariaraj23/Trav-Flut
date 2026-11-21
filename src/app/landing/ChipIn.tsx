"use client";

import { useEffect, useRef, useState } from "react";
import {
  CHIP_IN_CURRENCIES,
  CHIP_IN_LIMITS,
  CHIP_IN_PRESETS,
  chipInSymbol,
  type ChipInCurrency,
} from "@/lib/chipIn";

type PaymentWatch = {
  interval: number | null;
  timeout: number | null;
  generation: number;
};

function stopPaymentWatch(watch: PaymentWatch) {
  watch.generation += 1;
  if (watch.interval != null) {
    window.clearInterval(watch.interval);
    watch.interval = null;
  }
  if (watch.timeout != null) {
    window.clearTimeout(watch.timeout);
    watch.timeout = null;
  }
}

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
  const [currency, setCurrency] = useState<ChipInCurrency>("INR");
  const [selected, setSelected] = useState<number | "other">(100);
  const [custom, setCustom] = useState("");
  const [name, setName] = useState("");
  const [status, setStatus] = useState<"idle" | "opening" | "error">("idle");
  const [notice, setNotice] = useState("");
  const watchRef = useRef<PaymentWatch>({ interval: null, timeout: null, generation: 0 });

  useEffect(() => {
    const watch = watchRef.current;
    return () => stopPaymentWatch(watch);
  }, []);

  const limits = CHIP_IN_LIMITS[currency];
  const symbol = chipInSymbol(currency);
  const amount = selected === "other" ? Number(custom) : selected;
  const amountReady = Number.isInteger(amount) && amount >= limits.min && amount <= limits.max;
  const amountLabel = `${symbol}${currency === "INR" ? amount.toLocaleString("en-IN") : amount}`;

  function chooseCurrency(next: ChipInCurrency) {
    setCurrency(next);
    setSelected(next === "INR" ? 100 : 10);
    setCustom("");
    setNotice("");
    setStatus("idle");
  }

  async function chipIn() {
    if (!amountReady) {
      const maxLabel = currency === "INR" ? limits.max.toLocaleString("en-IN") : String(limits.max);
      setStatus("error");
      setNotice(`Enter a whole amount from ${symbol}${limits.min} to ${symbol}${maxLabel}.`);
      return;
    }
    setStatus("opening");
    setNotice("");
    const watch = watchRef.current;
    stopPaymentWatch(watch);
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
        body: JSON.stringify({ amount, currency, name }),
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
          stopPaymentWatch(watch);
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
            // The check keeps running after the window closes, so a capture
            // that lands late can still open the thank-you page. Leaving the
            // page stops it.
          },
        },
      });
      checkout.on("payment.failed", () => {
        settled = true;
        stopPaymentWatch(watch);
        window.location.assign("/thanks?problem=1");
      });
      const orderId = data.orderId;
      const generation = watch.generation;
      watch.interval = window.setInterval(async () => {
        if (watch.generation !== generation || settled) return;
        try {
          const statusResponse = await fetch(`/api/chip-in/status?orderId=${encodeURIComponent(orderId)}`);
          const statusBody = await statusResponse.json().catch(() => ({}));
          if (statusBody.status !== "paid" || watch.generation !== generation || settled) return;
          settled = true;
          stopPaymentWatch(watch);
          window.focus();
          window.location.assign("/thanks");
        } catch {
          // The next check asks again.
        }
      }, 1000);
      watch.timeout = window.setTimeout(() => {
        if (watch.generation === generation) stopPaymentWatch(watch);
      }, 90000);
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
            Rupees or dollars. One step, no account.
          </p>
        </div>
        <div className="flex flex-col items-start gap-3">
          <div className="flex gap-2" role="group" aria-label="Currency">
            {CHIP_IN_CURRENCIES.map((value) => (
              <button
                key={value}
                type="button"
                onClick={() => chooseCurrency(value)}
                className={`rounded-full px-4 py-2 text-sm font-medium ${
                  currency === value ? "bg-ink text-cream" : "bg-white text-ink"
                }`}
                aria-pressed={currency === value}
              >
                {value === "USD" ? "USD" : "INR"}
              </button>
            ))}
          </div>
          {currency === "USD" && (
            <p className="text-sm text-ink-soft">Dollars are charged to a card.</p>
          )}
          <div className="flex flex-wrap gap-2" role="group" aria-label="Amount">
            {CHIP_IN_PRESETS[currency].map((preset) => (
              <button
                key={preset}
                type="button"
                onClick={() => {
                  setSelected(preset);
                  setNotice("");
                  setStatus("idle");
                }}
                className={`rounded-full px-4 py-2 text-sm font-medium ${
                  selected === preset ? "bg-ink text-cream" : "bg-white text-ink"
                }`}
                aria-pressed={selected === preset}
              >
                {symbol}
                {preset}
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
              {currency === "USD" ? "Amount in dollars" : "Amount in rupees"}
              <input
                className="mt-2 w-36 rounded-2xl border border-ink/10 bg-white px-4 py-2 text-base outline-none focus:border-accent"
                inputMode="numeric"
                value={custom}
                autoFocus
                onChange={(event) =>
                  setCustom(event.target.value.replace(/[^\d]/g, "").slice(0, currency === "USD" ? 3 : 5))
                }
              />
            </label>
          )}
          <button
            type="button"
            onClick={chipIn}
            disabled={status === "opening" || !amountReady}
            className="inline-flex items-center justify-center rounded-full bg-accent px-5 py-3 text-base font-medium text-white transition hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
          >
            {status === "opening" ? "Opening…" : amountReady ? `Chip in ${amountLabel}` : "Chip in"}
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
