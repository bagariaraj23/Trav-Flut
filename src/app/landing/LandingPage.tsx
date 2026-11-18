import AuthLink from "./AuthLink";
import ProductFrame from "./ProductFrame";

const features = [
  {
    title: "A thread, not a photo dump",
    body: "Notes, photos, and places stay in the order you lived them.",
  },
  {
    title: "Live on Home",
    body: "Friends can follow the trip while it is still happening.",
  },
  {
    title: "Split the bill",
    body: "See who paid, who owes, and settle up on the Money pane.",
  },
  {
    title: "One story at the end",
    body: "Each person publishes their own final post, from the photos they took.",
  },
  {
    title: "Talk on the trip",
    body: "Direct messages, groups, and a room that belongs to the trip.",
  },
  {
    title: "Choose who sees you",
    body: "Discover people and trips. Follow, Restrict, or Block.",
  },
];

const steps = [
  {
    number: "01",
    title: "Start a trip",
    body: "Set the dates and invite the people who are actually going.",
  },
  {
    number: "02",
    title: "Thread it as you go",
    body: "Add a note, a photo, or a place while you are there.",
  },
  {
    number: "03",
    title: "Publish the story",
    body: "When the trip ends, each person writes the post they want to keep.",
  },
];

const resetTitles: Record<string, string> = {
  "invalid-reset-link": "Invalid reset link",
  "expired-reset-link": "Expired reset link",
  "already-used": "Link already used",
};

export default function LandingPage({
  error,
  message,
}: {
  error: string | null;
  message: string | null;
}) {
  const resetTitle = error ? resetTitles[error] ?? "Something went wrong" : null;

  return (
    <div className="min-h-screen bg-cream text-ink">
      {resetTitle && (
        <div className="border-b border-red-200 bg-red-50 px-5 py-3 text-center text-sm text-red-800">
          <p className="font-medium">{resetTitle}</p>
          <p className="mt-1">
            {message || "This password reset link cannot be used. Request a new one from the app."}
          </p>
        </div>
      )}

      <header className="sticky top-0 z-10 border-b border-ink/5 bg-cream/90 backdrop-blur">
        <div className="mx-auto flex max-w-6xl items-center justify-between gap-3 px-5 py-3 sm:px-8">
          <a href="/" className="flex min-w-0 items-center gap-2">
            <img
              src="/tripthread-icon.svg"
              alt=""
              className="h-9 w-9 shrink-0 sm:hidden"
            />
            <span className="truncate font-display text-xl tracking-tight sm:hidden">
              TripThread
            </span>
            <img
              src="/tripthread-logo.svg"
              alt="TripThread"
              className="hidden h-8 sm:block"
            />
          </a>
          <nav className="flex shrink-0 items-center gap-1 sm:gap-2" aria-label="Account">
            <a
              href="/support"
              className="inline-flex items-center rounded-full px-3 py-2 text-sm font-medium text-ink hover:bg-mist focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
            >
              Support
            </a>
            <AuthLink path="login" variant="secondary">
              Log in
            </AuthLink>
            <AuthLink path="signup" variant="primary">
              Get started
            </AuthLink>
          </nav>
        </div>
      </header>

      <main>
        <section className="mx-auto grid max-w-6xl items-center gap-12 px-5 py-14 sm:px-8 sm:py-20 lg:grid-cols-[1.1fr_0.9fr] lg:py-24">
          <div>
            <p className="text-sm font-medium uppercase tracking-[0.18em] text-accent">
              Travel, kept as a thread
            </p>
            <h1 className="mt-4 max-w-xl font-display text-5xl leading-[1.05] tracking-tight text-ink sm:text-6xl">
              Capture journeys. Share stories.
            </h1>
            <p className="mt-5 max-w-lg text-lg leading-relaxed text-ink-soft">
              Start a trip, write it as you go, and publish one story when you are home.
              Friends follow the thread while you are still on the road.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-3">
              <AuthLink path="signup" variant="primary" size="regular">
                Get started
              </AuthLink>
              <a
                href="#how-it-works"
                className="inline-flex items-center justify-center rounded-full px-5 py-3 text-base font-medium text-ink transition hover:bg-mist focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-accent"
              >
                See how it works
              </a>
            </div>
          </div>
          <ProductFrame />
        </section>

        <section className="border-t border-ink/5 bg-white" aria-labelledby="features-heading">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
            <h2 id="features-heading" className="max-w-xl font-display text-4xl tracking-tight">
              The trip stays in one place.
            </h2>
            <ul className="mt-10 grid gap-8 sm:grid-cols-2 lg:grid-cols-3">
              {features.map((feature) => (
                <li key={feature.title}>
                  <h3 className="font-display text-2xl tracking-tight">{feature.title}</h3>
                  <p className="mt-2 text-base leading-relaxed text-ink-soft">{feature.body}</p>
                </li>
              ))}
            </ul>
          </div>
        </section>

        <section id="how-it-works" className="scroll-mt-20" aria-labelledby="steps-heading">
          <div className="mx-auto max-w-6xl px-5 py-16 sm:px-8 sm:py-20">
            <h2 id="steps-heading" className="font-display text-4xl tracking-tight">
              How a trip works
            </h2>
            <ol className="mt-10 grid gap-8 md:grid-cols-3">
              {steps.map((step) => (
                <li key={step.number}>
                  <p className="font-display text-sm tracking-[0.18em] text-accent">{step.number}</p>
                  <h3 className="mt-2 font-display text-2xl tracking-tight">{step.title}</h3>
                  <p className="mt-2 text-base leading-relaxed text-ink-soft">{step.body}</p>
                </li>
              ))}
            </ol>
          </div>
        </section>

        <section className="px-5 pb-16 sm:px-8 sm:pb-20" aria-labelledby="close-heading">
          <div className="mx-auto flex max-w-6xl flex-col items-start gap-6 rounded-[28px] bg-ink px-6 py-12 text-cream sm:px-12 sm:py-14 lg:flex-row lg:items-center lg:justify-between">
            <div>
              <h2 id="close-heading" className="font-display text-4xl tracking-tight">
                The trip is the story.
              </h2>
              <p className="mt-3 max-w-md text-base leading-relaxed text-cream/75">
                Open TripThread, start the next one, and keep the thread as you travel.
              </p>
            </div>
            <div className="flex flex-wrap gap-3">
              <AuthLink path="signup" variant="inverse" size="regular">
                Get started
              </AuthLink>
              <AuthLink path="login" variant="inverse-ghost" size="regular">
                Log in
              </AuthLink>
            </div>
          </div>
        </section>
      </main>

      <footer className="border-t border-ink/5">
        <div className="mx-auto flex max-w-6xl flex-col gap-4 px-5 py-8 sm:flex-row sm:items-center sm:justify-between sm:px-8">
          <img src="/tripthread-logo.svg" alt="TripThread" className="h-7" />
          <div className="flex max-w-sm flex-col gap-2 sm:items-end">
            <a href="/support" className="text-sm font-medium text-ink underline-offset-4 hover:underline">
              Support
            </a>
            <p className="text-sm leading-relaxed text-ink-soft sm:text-right">
              Capture journeys. Share stories. Password reset links from your email open on this site.
            </p>
          </div>
        </div>
      </footer>
    </div>
  );
}
