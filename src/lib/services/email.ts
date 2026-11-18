import sgMail from "@sendgrid/mail";

const SENDGRID_API_KEY = process.env.SENDGRID_API_KEY!;
const MAIL_FROM = process.env.MAIL_FROM || "no-reply@your-domain";
const APP_NAME = process.env.APP_NAME || "TripThread";
const DEBUG = process.env.SENDGRID_DEBUG === "1";

if (SENDGRID_API_KEY) {
  sgMail.setApiKey(SENDGRID_API_KEY);
}

type ResetEmailArgs = { to: string; resetLink: string; ttlMinutes: number };
export async function sendPasswordResetEmail({ to, resetLink, ttlMinutes }: ResetEmailArgs) {
  if (!SENDGRID_API_KEY) {
    if (DEBUG) console.error("SENDGRID_API_KEY missing");
    return;
  }
  const msg = {
    to,
    from: MAIL_FROM,
    subject: `${APP_NAME}: Reset your password`,
    text: `This link expires in ${ttlMinutes} minutes.\n${resetLink}`,
    html: `<p>This link expires in <b>${ttlMinutes} minutes</b>.</p><p><a href="${resetLink}">Reset Password</a></p>`,
  };

  try {
    const res = await sgMail.send(msg as any);
    if (DEBUG) console.log("SendGrid OK:", res[0]?.statusCode, res[0]?.headers);
  } catch (e: any) {
    if (DEBUG) {
      console.error("SendGrid ERROR status:", e?.response?.statusCode);
      console.error("SendGrid ERROR body:", e?.response?.body || e);
    }
    // keep silent in prod semantics
  }
}

type SupportEmailArgs = {
  to: string;
  fromEmail: string;
  fromName?: string | null;
  userId?: string | null;
  message: string;
};

function escapeHtml(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

export async function sendSupportEmail({
  to,
  fromEmail,
  fromName,
  userId,
  message,
}: SupportEmailArgs): Promise<boolean> {
  if (!SENDGRID_API_KEY) {
    if (DEBUG) console.error("SENDGRID_API_KEY missing");
    return false;
  }
  const who = fromName ? `${fromName} <${fromEmail}>` : fromEmail;
  const account = userId ? `\nAccount: ${userId}` : "";
  const text = `From: ${who}${account}\n\n${message}`;
  const msg = {
    to,
    from: MAIL_FROM,
    replyTo: fromEmail,
    subject: `${APP_NAME}: Support message`,
    text,
    html: `<p><b>From:</b> ${escapeHtml(who)}</p>${
      userId ? `<p><b>Account:</b> ${escapeHtml(userId)}</p>` : ""
    }<p>${escapeHtml(message).replace(/\n/g, "<br>")}</p>`,
  };
  try {
    const res = await sgMail.send(msg as any);
    if (DEBUG) console.log("SendGrid OK:", res[0]?.statusCode);
    return true;
  } catch (e: any) {
    if (DEBUG) {
      console.error("SendGrid ERROR status:", e?.response?.statusCode);
      console.error("SendGrid ERROR body:", e?.response?.body || e);
    }
    return false;
  }
}

type SecEmailArgs = { to: string };
export async function sendSecurityEmail({ to }: SecEmailArgs) {
  if (!SENDGRID_API_KEY) return;
  const msg = {
    to,
    from: MAIL_FROM,
    subject: `${APP_NAME}: Your password was changed`,
    text: `If this wasn't you, contact support.`,
    html: `<p>Your password was changed.</p><p>If this wasn't you, contact support.</p>`,
  };
  try {
    const res = await sgMail.send(msg as any);
    if (DEBUG) console.log("SendGrid OK:", res[0]?.statusCode);
  } catch (e: any) {
    if (DEBUG) {
      console.error("SendGrid ERROR status:", e?.response?.statusCode);
      console.error("SendGrid ERROR body:", e?.response?.body || e);
    }
  }
}
