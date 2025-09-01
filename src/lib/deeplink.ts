const APP_SCHEME = process.env.APP_SCHEME || "travello";
const APP_RESET_WEB_URL = process.env.APP_RESET_WEB_URL || "https://app.your-domain/reset";

export function buildPasswordResetLink(rawToken: string) {
  const schemeUrl = `${APP_SCHEME}://reset?t=${encodeURIComponent(rawToken)}`;
  const webUrl = `${APP_RESET_WEB_URL}?t=${encodeURIComponent(rawToken)}`;
  return { schemeUrl, webUrl };
}