export const SUPPORT_EMAIL =
  process.env.SUPPORT_EMAIL?.trim() || "bagariaraj23@gmail.com";

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export type ParsedSupport =
  | { ok: true; honeypot: true }
  | { ok: true; honeypot: false; name: string; email: string | null; message: string }
  | { ok: false; error: string };

function asText(value: unknown, max: number): string {
  if (typeof value !== "string") return "";
  return value.replace(/\u0000/g, "").trim().slice(0, max);
}

export function parseSupportBody(input: unknown): ParsedSupport {
  const body = input && typeof input === "object" ? (input as Record<string, unknown>) : {};
  if (asText(body.website, 200)) {
    return { ok: true, honeypot: true };
  }

  const name = asText(body.name, 80);
  const emailRaw = asText(body.email, 200);
  const message = asText(body.message, 4000);

  if (message.length < 10) {
    return { ok: false, error: "Write at least a few words so we can help." };
  }
  if (emailRaw && !EMAIL_PATTERN.test(emailRaw)) {
    return { ok: false, error: "Enter a valid email so we can reply." };
  }

  return {
    ok: true,
    honeypot: false,
    name,
    email: emailRaw ? emailRaw.toLowerCase() : null,
    message,
  };
}
