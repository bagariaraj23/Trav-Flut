"use client";

import { FormEvent, useEffect, useRef, useState } from "react";
import { EARLY_ACCESS_TARGETS } from "@/lib/earlyAccess";

const inputClass =
  "mt-2 w-full rounded-2xl border border-ink/10 bg-white px-4 py-3 text-base text-ink outline-none focus:border-accent";

type Platform = "android" | "ios";

type Board = { current: number; target: number; ratio: number };

type Boards = { android: Board; ios: Board };

const SPARKS = [
  [0, -30],
  [22, -18],
  [26, 10],
  [8, 28],
  [-18, 22],
  [-28, 4],
  [-16, -22],
] as const;

function useCountUp(target: number | null, resetKey: string) {
  const [shown, setShown] = useState(0);
  const shownRef = useRef(0);
  const keyRef = useRef(resetKey);

  useEffect(() => {
    if (target == null) return;
    const switched = keyRef.current !== resetKey;
    keyRef.current = resetKey;
    const from = switched ? 0 : shownRef.current;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce || from === target) {
      shownRef.current = target;
      setShown(target);
      return;
    }
    const start = performance.now();
    const duration = 900;
    let frame = 0;
    const tick = (now: number) => {
      const t = Math.min((now - start) / duration, 1);
      const eased = 1 - Math.pow(1 - t, 3);
      const value = Math.round(from + (target - from) * eased);
      shownRef.current = value;
      setShown(value);
      if (t < 1) frame = requestAnimationFrame(tick);
    };
    frame = requestAnimationFrame(tick);
    return () => cancelAnimationFrame(frame);
  }, [target, resetKey]);

  return shown;
}

function AndroidMark() {
  return (
    <svg viewBox="0 0 32 32" className="h-9 w-9" aria-hidden="true">
      <g fill="currentColor" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round">
        <path d="M11.2 9.2 9.2 6" fill="none" />
        <path d="M20.8 9.2 22.8 6" fill="none" />
        <rect x="8" y="10" width="16" height="11" rx="5.5" stroke="none" />
        <circle cx="13.2" cy="14.6" r="1.15" fill="white" stroke="none" />
        <circle cx="18.8" cy="14.6" r="1.15" fill="white" stroke="none" />
        <path d="M10.2 21.4v3.4M21.8 21.4v3.4M8 16.2H5.4M24 16.2h2.6" fill="none" />
      </g>
    </svg>
  );
}

function AppleMark() {
  return (
    <svg viewBox="0 0 32 32" className="h-8 w-8" aria-hidden="true">
      <path
        fill="currentColor"
        d="M19.6 9.1c1-.1 2.2-.8 2.9-1.8.6-.9 1.1-2.1.9-3.3-1 .1-2.2.7-2.9 1.6-.6.8-1.2 2.1-.9 3.5z"
      />
      <path
        fill="currentColor"
        d="M21.8 12.2c-1.6-1-3.3-.4-4.1-.4s-2.2-.9-3.7-.9c-1.9 0-3.6 1.1-4.6 2.8-2 3.4-.5 8.5 1.4 11.3.9 1.4 2 2.9 3.5 2.8 1.4-.1 1.9-.9 3.6-.9s2.1.9 3.6.9c1.5 0 2.5-1.4 3.4-2.7.7-1 1.2-2.1 1.5-3.3-3.8-1.4-3.2-6.7-1.6-8.2-1.1-.8-2.1-1.2-2-1.4z"
      />
    </svg>
  );
}

function isBoard(value: unknown): value is Board {
  if (!value || typeof value !== "object") return false;
  const board = value as Board;
  return (
    typeof board.current === "number" &&
    typeof board.target === "number" &&
    typeof board.ratio === "number"
  );
}

function readBoards(data: unknown): Boards | null {
  if (!data || typeof data !== "object") return null;
  const body = data as { android?: unknown; ios?: unknown };
  if (!isBoard(body.android) || !isBoard(body.ios)) return null;
  return { android: body.android, ios: body.ios };
}

export default function EarlyAccess() {
  const [boards, setBoards] = useState<Boards | null>(null);
  const [name, setName] = useState("");
  const [email, setEmail] = useState("");
  const [platform, setPlatform] = useState<Platform>("android");
  const [website, setWebsite] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [notice, setNotice] = useState("");
  const [pop, setPop] = useState<{ platform: Platform; id: number } | null>(null);
  const board = boards?.[platform] ?? null;
  const shown = useCountUp(board?.current ?? null, platform);
  const ratio = board?.ratio ?? 0;
  const radius = 52;
  const circumference = 2 * Math.PI * radius;
  const dash = circumference * (1 - ratio);
  const accent = platform === "android" ? "#3DDC84" : "#1C1917";
  const fallbackTarget = platform === "android" ? EARLY_ACCESS_TARGETS.ANDROID : EARLY_ACCESS_TARGETS.IOS;
  const targetLabel = board?.target ?? fallbackTarget;
  const celebrating = pop?.platform === platform ? pop.id : 0;
  const counted = useRef<Record<Platform, number | null>>({ android: null, ios: null });

  useEffect(() => {
    if (!boards) return;
    const previous = counted.current[platform];
    const next = boards[platform].current;
    counted.current = {
      android: boards.android.current,
      ios: boards.ios.current,
    };
    if (previous != null && next > previous) {
      setPop((current) => ({ platform, id: (current?.id ?? 0) + 1 }));
    }
  }, [boards, platform]);

  useEffect(() => {
    let cancelled = false;
    async function load() {
      try {
        const response = await fetch("/api/early-access");
        const data = response.ok ? await response.json() : null;
        const next = readBoards(data);
        if (!cancelled && next) setBoards(next);
      } catch {
        // The ring keeps the last count it showed.
      }
    }
    void load();
    return () => {
      cancelled = true;
    };
  }, []);

  function choosePlatform(next: Platform) {
    setPlatform(next);
    setStatus("idle");
    setNotice("");
  }

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
      const next = readBoards(data);
      if (next) setBoards(next);
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
            <div className="relative h-28 w-28">
              <svg
                viewBox="0 0 120 120"
                className="h-28 w-28"
                role="img"
                aria-label={
                  board
                    ? `${board.current} of ${board.target} ${platform === "android" ? "Android" : "iPhone"}`
                    : "Early access count loading"
                }
              >
                <circle cx="60" cy="60" r={radius} fill="none" stroke="#EDE7DC" strokeWidth="8" />
                <circle
                  cx="60"
                  cy="60"
                  r={radius}
                  fill="none"
                  stroke={accent}
                  strokeWidth="8"
                  strokeLinecap="round"
                  strokeDasharray={circumference}
                  strokeDashoffset={dash}
                  transform="rotate(-90 60 60)"
                  className="transition-[stroke-dashoffset,stroke] duration-1000 ease-out motion-reduce:transition-none"
                />
              </svg>
              <div className="pointer-events-none absolute inset-0 flex items-center justify-center" style={{ color: accent }}>
                {board == null ? (
                  <span className="h-3 w-3 rounded-full bg-current animate-pulse motion-reduce:animate-none" />
                ) : (
                  <span key={`${platform}-${celebrating}`} className="early-access-pop">
                    {platform === "android" ? <AndroidMark /> : <AppleMark />}
                  </span>
                )}
                {celebrating > 0 &&
                  SPARKS.map(([x, y], index) => (
                    <span
                      key={`${celebrating}-${index}`}
                      className="early-access-spark absolute h-1.5 w-1.5 rounded-full bg-current"
                      style={{
                        ["--spark-x" as string]: `${x}px`,
                        ["--spark-y" as string]: `${y}px`,
                        animationDelay: `${index * 30}ms`,
                      }}
                    />
                  ))}
              </div>
            </div>
            <div>
              <p className="font-display text-5xl tabular-nums tracking-tight">
                {board == null ? "—" : shown}
              </p>
              <p className="mt-1 text-sm text-ink-soft">
                of {targetLabel} {platform === "android" ? "Android" : "iPhone"}
              </p>
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
                    onChange={() => choosePlatform(value)}
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
