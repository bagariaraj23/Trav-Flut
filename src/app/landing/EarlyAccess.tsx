"use client";

import { FormEvent, useEffect, useState } from "react";

const inputClass =
  "mt-2 w-full rounded-2xl border border-ink/10 bg-white px-4 py-3 text-base text-ink outline-none focus:border-accent";

type Platform = "android" | "ios";

type Progress = { current: number; target: number; ratio: number };

function useCountUp(target: number | null) {
  const [shown, setShown] = useState(0);

  useEffect(() => {
    if (target == null) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) {
      setShown(target);
      return;
    }
    const start = performance.now();
    const from = 0;
    const duration = 900;
    let frame = 0;
    const tick = (now: number) => {
      const t = Math.min((now - start) / duration, 1);
      const eased = 1 - Math.pow(1 - t, 3);
      setShown(Math.round(from + (target - from) * eased));
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target]);

  return shown;
}

export default function EarlyAccess() {
  const [progress, setProgress] = useState<Progress | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [platform, setPlatform] = useState<Platform>("android");
  const [website, setWebsite] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [notice, setNotice] = useState("");
  const shown = useCountUp(progress?.current ?? null);
  const ratio = progress?.ratio ?? 0;
  const radius = 52;
  const circumference = 2 * Math.PI * radius;
  const dash = circumference * (1 - ratio);

  useEffect(() => {
    let cancelled = false;
    fetch("/api/early-access")
      .then((response) => (response.ok ? response.json() : null))
      .then((data) => {
        if (cancelled || !data || typeof data.current !== "number") return;
        setProgress({
          current: data.current,
          target: data.target,
          ratio: data.ratio,
        });
      })
      .catch(() => {});
    return () => {
      cancelled = true;
    };
  }, []);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("sending");
    setNotice("");
    try {
      const response = await fetch("/api/early-access", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email, platform, website }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        setStatus("error");
        setNotice(typeof data.error === "string" ? data.error : "Could not save that.");
        return;
      }
      if (typeof data.current === "number") {
        setProgress({
          current: data.current,
          target: data.target,
          ratio: data.ratio,
        });
      }
      setStatus("sent");
      if (data.created === false) {
        setNotice("This email is already on the list.");
        return;
      }
      if (platform === "android") {
        setNotice(
          data.emailed
            ? "You're on the list. Check your email for the download link."
            : "You're on the list. We'll email the download link to this address."
        );
        return;
      }
      setNotice(
        data.emailed
          ? "Request received. Check your email."
          : "Request received. We'll email this address when it's ready."
      );
    } catch {
      setStatus("error");
      setNotice("Could not save that.");
    }
  }

  const targetLabel = progress?.target ?? 100;
  const currentLabel = progress ? shown : null;

  return (
    <section id="early-access" className="scroll-mt-20 border-t border-ink/5 bg-white" aria-labelledby="early-access-heading">
      <div className="mx-auto grid max-w-6xl items-center gap-12 px-5 py-16 sm:px-8 sm:py-20 lg:grid-cols-[0.8fr_1.2fr]">
        <div className="flex flex-col items-start gap-6">
          <div>
            <p className="text-sm font-medium uppercase tracking-[0.18em] text-accent">Early access</p>
            <h2 id="early-access-heading" className="mt-3 font-display text-4xl tracking-tight">
              Get the app before everyone else.
            </h2>
            <p className="mt-3 max-w-md text-base leading-relaxed text-ink-soft">
              Android gets an email with the download. iPhone is a request, and we'll write when it's ready.
            </p>
          </div>
          <div className="flex items-center gap-5" aria-live="polite">
            <svg viewBox="0 0 120 120" className="h-28 w-28" role="img" aria-label={progress ? `${progress.current} of ${progress.target}` : "Early access count loading"}>
              <circle cx="60" cy="60" r={radius} fill="none" stroke="#EDE7DC" strokeWidth="8" />
              <circle
                cx="60"
                cy="60"
                r={radius}
                fill="none"
                stroke="#1D6FE8"
                strokeWidth="8"
                strokeLinecap="round"
                strokeDasharray={circumference}
                strokeDashoffset={dash}
                transform="rotate(-90 60 60)"
                className="transition-[stroke-dashoffset] duration-1000 ease-out motion-reduce:transition-none"
              />
              {currentLabel == null && (
                <circle cx="60" cy="60" r="6" fill="#1D6FE8" className="origin-center animate-pulse motion-reduce:animate-none" />
              )}
            </svg>
            <div>
              <p className="font-display text-5xl tabular-nums tracking-tight">
                {currentLabel == null ? "—" : currentLabel}
              </p>
              <p className="mt-1 text-sm text-ink-soft">of {targetLabel}</p>
            </div>
          </div>
        </div>

        <form onSubmit={onSubmit} className="relative rounded-[28px] bg-cream p-6 sm:p-8">
          <div className="grid gap-4 sm:grid-cols-2">
            <label className="block text-sm font-medium">
              Name
              <input
                className={inputClass}
                value={name}
                onChange={(event) => setName(event.target.value)}
                autoComplete="name"
                maxLength={80}
              />
            </label>
            <label className="block text-sm font-medium">
              Email
              <input
                className={inputClass}
                type="email"
                required
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                autoComplete="email"
                maxLength={200}
              />
            </label>
          </div>
          <fieldset className="mt-5">
            <legend className="text-sm font-medium">Phone</legend>
            <div className="mt-2 grid grid-cols-2 gap-2">
              {(
                [
                  ["android", "Android"],
                  ["ios", "iPhone"],
                ] as const
              ).map(([value, label]) => (
                <label
                  key={value}
                  className={`flex cursor-pointer items-center justify-center rounded-full border px-4 py-3 text-sm font-medium ${
                    platform === value
                      ? "border-ink bg-ink text-cream"
                      : "border-ink/10 bg-white text-ink"
                  }`}
                >
                  <input
                    type="radio"
                    name="platform"
                    value={value}
                    checked={platform === value}
                    onChange={() => setPlatform(value)}
                    className="sr-only"
                  />
                  {label}
                </label>
              ))}
            </div>
          </fieldset>
          <p className="mt-4 text-sm leading-relaxed text-ink-soft">
            {platform === "android"
              ? "We'll email you a link to download the Android app."
              : "Send a request for early access on iPhone."}
          </p>
          <label className="absolute left-[-9999px]" aria-hidden="true">
            Website
            <input
              tabIndex={-1}
              autoComplete="off"
              value={website}
              onChange={(event) => setWebsite(event.target.value)}
            />
          </label>
          <button
            type="submit"
            disabled={status === "sending"}
            className="mt-6 inline-flex items-center justify-center rounded-full bg-accent px-5 py-3 text-base font-medium text-white transition hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent disabled:opacity-60"
          >
            {status === "sending" ? "Sending…" : platform === "android" ? "Get the Android app" : "Request early access"}
          </button>
          {notice && (
            <p className={`mt-4 text-sm ${status === "error" ? "text-red-800" : "text-ink"}`} role="status">
              {notice}
            </p>
          )}
        </form>
      </div>
    </section>
  );
}
