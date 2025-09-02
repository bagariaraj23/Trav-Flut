import sgMail from "@sendgrid/mail";
import { ms } from "zod/v4/locales";

const SENDGRID_API_KEY = process.env.SENDGRID_API_KEY!;
const MAIL_FROM = process.env.MAIL_FROM || "no-reply@your-domain";
const APP_NAME = process.env.APP_NAME || "TripThread";
const DEBUG = process.env.SENDGRID_DEBUG === "1";

if (SENDGRID_API_KEY) {
  sgMail.setApiKey(SENDGRID_API_KEY);
}

type ResetEmailArgs = {
  to: string;
  resetLink: string;
  appLink:string;
  ttlMinutes: number;
};
export async function sendPasswordResetEmail({ to, resetLink, appLink, ttlMinutes }: ResetEmailArgs) {
  if (!SENDGRID_API_KEY) {
    if (DEBUG) console.error("SENDGRID_API_KEY missing");
    return;
  }
  const msg = {
    to,
    from: MAIL_FROM,
    subject: `${APP_NAME}: Reset your password`,
    text: `This link expires in ${ttlMinutes} minutes.\nApp: ${appLink}\nWeb: ${resetLink}`,
    html: `<p>This link expires in <b>${ttlMinutes} minutes</b>.</p>
           <p><a href="${`${appLink}`}">Open in App: ${appLink}</a> (mobile only)</p>
           <p><a href="${resetLink}">Open in Browser</a></p>`,
  };

  console.log("Sending password reset email to:", JSON.stringify(msg, null, 2));

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
