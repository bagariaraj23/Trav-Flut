const APP_SCHEME = process.env.APP_SCHEME || "tripthread";
const APP_RESET_WEB_URL =
  process.env.APP_RESET_WEB_URL || "https://app.your-domain/reset";

export function buildPasswordResetLink(rawToken: string, email: string) {
  const schemeUrl = `${APP_SCHEME}://reset?t=${encodeURIComponent(
    rawToken
  )}&email=${encodeURIComponent(email)}`;
  const webUrl = `${APP_RESET_WEB_URL}?t=${encodeURIComponent(
    rawToken
  )}&email=${encodeURIComponent(email)}`;
  return { schemeUrl, webUrl };
}
