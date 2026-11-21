"use client";

import { FormEvent, useState } from "react";

const inputClass =
  "mt-2 w-full rounded-2xl border border-ink/10 bg-white px-4 py-3 text-base text-ink outline-none focus:border-accent";

export default function SupportForm({ email }: { email: string }) {
  const [name, setName] = useState("");
  const [from, setFrom] = useState("");
  const [message, setMessage] = useState("");
  const [website, setWebsite] = useState("");
  const [status, setStatus] = useState<"idle" | "sending" | "sent" | "error">("idle");
  const [error, setError] = useState("");

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setStatus("sending");
    setError("");
    try {
      const response = await fetch("/api/support", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ name, email: from, message, website }),
      });
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        setStatus("error");
        setError(typeof data.error === "string" ? data.error : "Could not send your message.");
        return;
      }
      setStatus("sent");
    } catch {
      setStatus("error");
      setError("Could not send your message.");
    }
  }

  const mailto = `mailto:${email}?subject=${encodeURIComponent("TripThread support")}&body=${encodeURIComponent(message)}`;

  return (
    <form onSubmit={onSubmit} className="mt-8 max-w-xl">
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
      <label className="mt-4 block text-sm font-medium">
        Email
        <input
          className={inputClass}
          type="email"
          required
          value={from}
          onChange={(event) => setFrom(event.target.value)}
          autoComplete="email"
        />
      </label>
      <label className="mt-4 block text-sm font-medium">
        What happened?
        <textarea
          className={`${inputClass} min-h-40 resize-y`}
          required
          minLength={10}
          maxLength={4000}
          value={message}
          onChange={(event) => setMessage(event.target.value)}
        />
      </label>
      <div className="hidden" aria-hidden="true">
        <label>
          Website
          <input
            tabIndex={-1}
            autoComplete="off"
            value={website}
            onChange={(event) => setWebsite(event.target.value)}
          />
        </label>
      </div>

      {status === "sent" ? (
        <p className="mt-6 text-base" role="status">
          Sent. We will reply by email.
        </p>
      ) : (
        <button
          type="submit"
          disabled={status === "sending"}
          className="mt-6 inline-flex rounded-full bg-accent px-5 py-3 text-base font-medium text-white disabled:opacity-50"
        >
          {status === "sending" ? "Sending…" : "Send"}
        </button>
      )}

      {status === "error" && (
        <p className="mt-4 text-sm text-red-800" role="alert">
          {error}{" "}
          <a className="underline" href={mailto}>
            Email {email}
          </a>
        </p>
      )}
    </form>
  );
}
