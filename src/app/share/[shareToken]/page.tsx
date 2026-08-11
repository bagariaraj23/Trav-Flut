"use client";

import { useEffect, useState } from "react";
import { useParams } from "next/navigation";

/**
 * Public landing page for shared links (https://…/share/{token}).
 * Attempts to open the native app via custom URL schemes; falls back to manual “Open in app” links.
 * Configure Universal Links / App Links on this host (see public/.well-known/) for one-tap opens when installed.
 */
export default function ShareBridgePage() {
  const params = useParams();
  const shareToken = params?.shareToken as string | undefined;
  const [showFallback, setShowFallback] = useState(false);

  useEffect(() => {
    if (!shareToken) return;
    const encoded = encodeURIComponent(shareToken);
    const primary = `tripthread://share/${encoded}`;
    try {
      window.location.href = primary;
    } catch {
      /* ignore */
    }
    const t = window.setTimeout(() => setShowFallback(true), 1200);
    return () => window.clearTimeout(t);
  }, [shareToken]);

  if (!shareToken) {
    return (
      <main style={{ padding: 24, fontFamily: "system-ui, sans-serif" }}>
        <p>Invalid share link.</p>
      </main>
    );
  }

  const encoded = encodeURIComponent(shareToken);

  return (
    <main style={{ padding: 24, maxWidth: 480, fontFamily: "system-ui, sans-serif" }}>
      <h1 style={{ fontSize: "1.25rem" }}>TripThread</h1>
      <p>Opening the TripThread app…</p>
      {showFallback && (
        <div style={{ marginTop: 24 }}>
          <p style={{ color: "#555" }}>
            If the app did not open, tap below. Install TripThread if you do not have it yet.
          </p>
          <p style={{ marginTop: 16 }}>
            <a
              href={`tripthread://share/${encoded}`}
              style={{
                display: "inline-block",
                padding: "12px 16px",
                background: "#1565c0",
                color: "#fff",
                textDecoration: "none",
                borderRadius: 8,
                fontWeight: 600,
              }}
            >
              Open in TripThread
            </a>
          </p>
        </div>
      )}
    </main>
  );
}
