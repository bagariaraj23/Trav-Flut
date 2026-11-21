import SupportForm from "./SupportForm";
import { SUPPORT_EMAIL } from "@/lib/supportMessage";

export const metadata = {
  title: "Support · TripThread",
  description: "Send a note to the TripThread team.",
};

export default function SupportPage() {
  return (
    <div className="min-h-screen bg-cream text-ink">
      <header className="border-b border-ink/5">
        <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-4 sm:px-8">
          <a href="/" className="font-display text-2xl tracking-tight">
            TripThread
          </a>
          <a href="/" className="text-sm font-medium text-ink-soft hover:text-ink">
            Back
          </a>
        </div>
      </header>
      <main className="mx-auto max-w-6xl px-5 py-14 sm:px-8">
        <p className="text-sm font-medium uppercase tracking-[0.18em] text-accent">
          Support
        </p>
        <h1 className="mt-3 max-w-xl font-display text-5xl tracking-tight">
          Tell us what went wrong.
        </h1>
        <p className="mt-4 max-w-xl text-lg leading-relaxed text-ink-soft">
          Write it here and it is emailed to the TripThread team. Include the
          trip name if this is about a trip.
        </p>
        <SupportForm email={SUPPORT_EMAIL} />
      </main>
    </div>
  );
}
