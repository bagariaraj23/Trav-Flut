/** Flutter web origin for Log in and Sign up. Empty until the Railway URL is set. */
export function appAuthHref(path: "login" | "signup"): string | null {
  const raw = process.env.NEXT_PUBLIC_APP_WEB_URL?.trim() ?? "";
  if (!raw) return null;
  const origin = raw.replace(/\/+$/, "");
  if (!/^https?:\/\//i.test(origin)) return null;
  return `${origin}/${path}`;
}
