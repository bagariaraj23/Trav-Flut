export const EARLY_ACCESS_TARGET = 100;

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export type EarlyAccessPlatform = "ANDROID" | "IOS";

export type ParsedEarlyAccess =
  | { ok: true; honeypot: true }
  | {
      ok: true;
      honeypot: false;
      name: string | null;
      email: string;
      platform: EarlyAccessPlatform;
    }
  | { ok: false; error: string };

function asText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.replace(/\u0000/g, "").trim().slice(0, max);
}

export function parseEarlyAccessBody(input: unknown): ParsedEarlyAccess {
  const body = input && typeof input === "object" ? (input as Record<string, unknown>) : {};
  if (asText(body.website, 200)) {
    return { ok: true, honeypot: true };
  }

  const name = asText(body.name, 80);
  const email = asText(body.email, 200).toLowerCase();
  const platformRaw = asText(body.platform, 20).toLowerCase();

  if (!email || !EMAIL_PATTERN.test(email)) {
    return { ok: false, error: "Enter a valid email." };
  }
  if (platformRaw !== "android" && platformRaw !== "ios") {
    return { ok: false, error: "Choose Android or iPhone." };
  }

  return {
    ok: true,
    honeypot: false,
    name: name || null,
    email,
    platform: platformRaw === "android" ? "ANDROID" : "IOS",
  };
}

export function earlyAccessProgress(current: number, target = EARLY_ACCESS_TARGET) {
  const safeCurrent = Number.isFinite(current) ? Math.max(0, Math.floor(current)) : 0;
  const safeTarget = Number.isFinite(target) ? Math.max(1, Math.floor(target)) : EARLY_ACCESS_TARGET;
  return {
    current: safeCurrent,
    target: safeTarget,
    ratio: Math.min(safeCurrent / safeTarget, 1),
  };
}
