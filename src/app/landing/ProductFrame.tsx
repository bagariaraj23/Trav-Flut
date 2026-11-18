const entries = [
  {
    kind: "Note",
    title: "The train pulled in just after sunrise.",
    meta: "Maya · 8:40",
  },
  {
    kind: "Place",
    title: "Jaisalmer Fort",
    meta: "Saved on the map",
  },
  {
    kind: "Money",
    title: "Dinner at the haveli",
    meta: "₹2,400 · split 3 ways",
  },
];

export default function ProductFrame() {
  return (
    <div className="relative mx-auto w-full max-w-md">
      <div
        className="absolute -inset-6 -z-10 rounded-[36px] bg-accent/10 blur-2xl"
        aria-hidden="true"
      />
      <article
        aria-label="Example trip thread"
        className="rounded-[28px] border border-ink/5 bg-card p-5 shadow-[0_24px_60px_-30px_rgba(28,25,23,0.45)] sm:p-6"
      >
        <div className="flex items-start justify-between gap-4">
          <div>
            <p className="text-xs font-medium uppercase tracking-[0.16em] text-ink-soft">
              Example
            </p>
            <h2 className="mt-1 font-display text-3xl text-ink">Coast week</h2>
            <p className="mt-1 text-sm text-ink-soft">22 May – 28 May</p>
          </div>
          <span className="inline-flex items-center gap-1.5 rounded-full bg-live/10 px-2.5 py-1 text-xs font-medium text-live">
            <span className="h-1.5 w-1.5 rounded-full bg-live" aria-hidden="true" />
            Live
          </span>
        </div>

        <ol className="mt-6 space-y-5 border-l border-mist pl-5">
          {entries.map((entry) => (
            <li key={entry.title} className="relative">
              <span
                className="absolute -left-[23px] top-1.5 h-2.5 w-2.5 rounded-full border-2 border-accent bg-card"
                aria-hidden="true"
              />
              <p className="text-xs font-medium uppercase tracking-[0.14em] text-ink-soft">
                {entry.kind}
              </p>
              <p className="mt-1 text-base text-ink">{entry.title}</p>
              <p className="mt-0.5 text-sm text-ink-soft">{entry.meta}</p>
            </li>
          ))}
        </ol>

        <div className="mt-6 rounded-2xl bg-cream px-4 py-3">
          <p className="text-xs font-medium uppercase tracking-[0.14em] text-ink-soft">
            When it ends
          </p>
          <p className="mt-1 text-sm text-ink">
            Each person publishes their own final post.
          </p>
        </div>
      </article>
    </div>
  );
}
