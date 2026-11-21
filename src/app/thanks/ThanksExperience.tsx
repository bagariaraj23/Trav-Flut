"use client";

import { useEffect, useMemo, useRef, useState } from "react";

const CONFETTI_COLORS = ["#1D6FE8", "#F4C95D", "#F08A8A", "#7DCE9A", "#FFFFFF", "#1C1917"];

type Piece = {
  x: number;
  y: number;
  vx: number;
  vy: number;
  w: number;
  h: number;
  color: string;
  rot: number;
  vr: number;
};

function burst(width: number, height: number): Piece[] {
  const originX = width / 2;
  const originY = height * 0.38;
  return Array.from({ length: 110 }, () => {
    const angle = Math.random() * Math.PI * 2;
    const speed = 4 + Math.random() * 8;
    return {
      x: originX,
      y: originY,
      vx: Math.cos(angle) * speed,
      vy: Math.sin(angle) * speed - 4,
      w: 6 + Math.random() * 7,
      h: 8 + Math.random() * 8,
      color: CONFETTI_COLORS[Math.floor(Math.random() * CONFETTI_COLORS.length)] ?? "#1D6FE8",
      rot: Math.random() * Math.PI,
      vr: (Math.random() - 0.5) * 0.3,
    };
  });
}

function Confetti() {
  const canvasRef = useRef<HTMLCanvasElement>(null);

  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const reduce = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (reduce) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const resize = () => {
      canvas.width = window.innerWidth;
      canvas.height = window.innerHeight;
    };
    resize();
    window.addEventListener("resize", resize);
    const pieces = burst(canvas.width, canvas.height);
    let frame = 0;
    let raf = 0;

    const draw = () => {
      ctx.clearRect(0, 0, canvas.width, canvas.height);
      for (const piece of pieces) {
        piece.x += piece.vx;
        piece.y += piece.vy;
        piece.vy += 0.12;
        piece.vx *= 0.995;
        piece.rot += piece.vr;
        ctx.save();
        ctx.translate(piece.x, piece.y);
        ctx.rotate(piece.rot);
        ctx.fillStyle = piece.color;
        ctx.globalAlpha = Math.max(0, 1 - frame / 220);
        ctx.fillRect(-piece.w / 2, -piece.h / 2, piece.w, piece.h);
        ctx.restore();
      }
      frame += 1;
      if (frame < 230) raf = requestAnimationFrame(draw);
      else ctx.clearRect(0, 0, canvas.width, canvas.height);
    };
    raf = requestAnimationFrame(draw);
    return () => {
      cancelAnimationFrame(raf);
      window.removeEventListener("resize", resize);
    };
  }, []);

  return <canvas ref={canvasRef} className="pointer-events-none fixed inset-0 z-40 h-full w-full" aria-hidden="true" />;
}

const RETURN_SECONDS = 8;

function bubblesFor(names: string[]) {
  const slots = Math.min(24, Math.max(names.length, names.length === 0 ? 0 : 12));
  return Array.from({ length: slots }, (_, index) => {
    const name = names[index % names.length] ?? "";
    return {
      name,
      left: (index * 41) % 92,
      delay: -((index * 1.7) % (15 + (index % 6) * 2.2)),
      duration: 15 + (index % 6) * 2.2,
      size: 78 + (index % 5) * 16,
      drift: ((index % 5) - 2) * 28,
      sway: 8 + (index % 4) * 6,
    };
  });
}

export default function ThanksExperience({
  names,
  problem,
}: {
  names: string[];
  problem: boolean;
}) {
  const bubbles = useMemo(() => bubblesFor(names), [names]);
  const [secondsLeft, setSecondsLeft] = useState(RETURN_SECONDS);

  useEffect(() => {
    if (problem) return;
    const started = Date.now();
    const tick = window.setInterval(() => {
      const left = Math.max(0, RETURN_SECONDS - Math.floor((Date.now() - started) / 1000));
      setSecondsLeft(left);
    }, 250);
    const timer = window.setTimeout(() => {
      window.location.assign("/");
    }, RETURN_SECONDS * 1000);
    return () => {
      window.clearInterval(tick);
      window.clearTimeout(timer);
    };
  }, [problem]);

  return (
    <div className="relative min-h-screen overflow-hidden bg-cream text-ink">
      <style>{`
        @keyframes bubble-rise {
          0% { transform: translate3d(0, 18vh, 0); opacity: 0; }
          12% { opacity: 1; }
          88% { opacity: 1; }
          100% { transform: translate3d(var(--drift), -120vh, 0); opacity: 0; }
        }
        @keyframes bubble-sway {
          0%, 100% { transform: translateX(0); }
          50% { transform: translateX(var(--sway)); }
        }
        .thanks-bubble {
          animation: bubble-rise var(--duration) linear var(--delay) infinite;
        }
        .thanks-bubble span {
          animation: bubble-sway 4.5s ease-in-out infinite;
        }
        @media (prefers-reduced-motion: reduce) {
          .thanks-field { height: auto; overflow: visible; }
          .thanks-bubble, .thanks-bubble span { animation: none; position: static; opacity: 1; transform: none; }
          .thanks-field { display: flex; flex-wrap: wrap; justify-content: center; gap: 0.75rem; padding: 1.5rem; }
        }
      `}</style>
      {!problem && <Confetti />}
      <div className="thanks-field pointer-events-none absolute inset-0 z-0" aria-hidden="true">
        {bubbles.map((bubble, index) => (
          <div
            key={`${bubble.name}-${index}`}
            className="thanks-bubble absolute bottom-0 flex items-center justify-center rounded-full border border-ink/10 bg-white/80 text-center shadow-[inset_0_8px_16px_rgba(255,255,255,0.9),0_12px_28px_rgba(28,25,23,0.08)]"
            style={{
              left: `${bubble.left}%`,
              width: bubble.size,
              height: bubble.size,
              ["--duration" as string]: `${bubble.duration}s`,
              ["--delay" as string]: `${bubble.delay}s`,
              ["--drift" as string]: `${bubble.drift}px`,
              ["--sway" as string]: `${bubble.sway}px`,
              background:
                index % 4 === 0
                  ? "rgba(255,255,255,0.78)"
                  : index % 4 === 1
                    ? "rgba(186,220,255,0.72)"
                    : index % 4 === 2
                      ? "rgba(255,228,196,0.78)"
                      : "rgba(237,231,220,0.88)",
            }}
          >
            <span className="max-w-[8rem] px-3 text-sm font-medium leading-tight text-ink">{bubble.name}</span>
          </div>
        ))}
      </div>
      <header className="relative z-30 mx-auto flex max-w-6xl items-center justify-between px-5 py-4 sm:px-8">
        <a href="/" className="font-display text-2xl tracking-tight">
          TripThread
        </a>
        <a href="/" className="text-sm font-medium text-ink-soft hover:text-ink">
          Back
        </a>
      </header>
      <main className="relative z-30 mx-auto flex min-h-[70vh] max-w-xl flex-col items-center justify-center px-5 pb-20 text-center">
        <div className="rounded-[2rem] bg-cream/85 px-6 py-10 shadow-[0_20px_60px_rgba(28,25,23,0.06)] backdrop-blur-md sm:px-12">
          <p className="text-sm font-medium uppercase tracking-[0.18em] text-accent">Chip in</p>
          <h1 className="mt-3 font-display text-5xl tracking-tight sm:text-6xl">
            {problem ? "The payment did not go through." : "Thank you for your support."}
          </h1>
          <p className="mx-auto mt-4 max-w-md text-lg leading-relaxed text-ink-soft">
            {problem
              ? "You can try again from the TripThread page. If your bank shows the payment, keep the receipt."
              : names.length > 0
                ? "It keeps TripThread going. The names drifting past are people who chipped in."
                : "It keeps TripThread going."}
          </p>
          {!problem && (
            <p className="mt-3 text-sm text-ink-soft" role="status">
              Taking you back to TripThread{secondsLeft > 0 ? ` in ${secondsLeft}s` : ""}.
            </p>
          )}
          {names.length > 0 && (
            <ul className="sr-only">
              {names.map((supporter) => (
                <li key={supporter}>{supporter}</li>
              ))}
            </ul>
          )}
          <a
            href={problem ? "/#chip-in" : "/"}
            className="mt-8 inline-flex items-center justify-center rounded-full bg-accent px-5 py-3 text-base font-medium text-white transition hover:opacity-90 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
          >
            {problem ? "Try again" : "Back to TripThread"}
          </a>
        </div>
      </main>
    </div>
  );
}
