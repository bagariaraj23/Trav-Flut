import crypto from "crypto";
import { prisma } from "@/lib/prisma";
import { buildPasswordResetLink } from "@/lib/deeplink";
import { sendPasswordResetEmail, sendSecurityEmail } from "@/lib/services/email";
import { recordSecurityEvent } from "@/lib/services/securityEvent";
import { revokeAllRefreshTokens } from "@/lib/services/token";
import { passwordPolicy } from "@/lib/password-policy";
import { z } from "zod";
import bcrypt from "bcryptjs";

const TTL_MIN = Number(process.env.RESET_TOKEN_TTL_MIN || 30);
const RESET_RETENTION_DAYS = Number(process.env.RESET_RETENTION_DAYS || 7);

const forgotSchema = z.object({ email: z.string().email() });
const resetSchema = z.object({ token: z.string().min(16), newPassword: passwordPolicy });

export async function requestReset(payload: unknown, ctx?: { ip?: string; userAgent?: string },hooks?: { onToken?: (token: string) => void }) {
  const { email } = forgotSchema.parse(payload);
  const user = await prisma.user.findUnique({ where: { email } });
  if (!user || (user as any).deletedAt) return;
  console.log(`${user}: user`);
  const rawToken = crypto.randomBytes(48).toString("base64url");
  const tokenHash = crypto.createHash("sha256").update(rawToken).digest();
  hooks?.onToken?.(rawToken);
  const expiresAt = new Date(Date.now() + TTL_MIN * 60 * 1000);
  await prisma.passwordReset.create({
    data: {
      userId: user.id,
      tokenHash,
      expiresAt,
      createdIp: ctx?.ip || null,
      userAgent: ctx?.userAgent || null,
    },
  });

  const { webUrl } = buildPasswordResetLink(rawToken);
  await sendPasswordResetEmail({ to: user.email, resetLink: webUrl, ttlMinutes: TTL_MIN });
  await recordSecurityEvent({ userId: user.id, type: "PASSWORD_RESET_REQUESTED" });
}

export async function resetWithToken(payload: unknown) {
  const { token, newPassword } = resetSchema.parse(payload);

  const tokenHash = crypto.createHash("sha256").update(token).digest();
  const reset = await prisma.passwordReset.findUnique({ where: { tokenHash } });
  if (!reset || reset.usedAt || reset.expiresAt < new Date()) return;

  const user = await prisma.user.findUnique({ where: { id: reset.userId } });
  if (!user || (user as any).deletedAt) return;

  const pwHash = await bcrypt.hash(newPassword, 10);
  await prisma.user.update({ where: { id: user.id }, data: { password: pwHash } });

  await prisma.passwordReset.update({ where: { id: reset.id }, data: { usedAt: new Date() } });

  await revokeAllRefreshTokens(user.id);

  await recordSecurityEvent({ userId: user.id, type: "PASSWORD_RESET_SUCCESS" });
  await recordSecurityEvent({ userId: user.id, type: "PASSWORD_CHANGED" });
  await sendSecurityEmail({ to: user.email });
}

export async function cleanupExpiredResets() {
  const cutoff = new Date(Date.now() - RESET_RETENTION_DAYS * 24 * 60 * 60 * 1000);
  await prisma.passwordReset.deleteMany({
    where: {
      OR: [{ usedAt: { not: null } }, { expiresAt: { lt: new Date() } }],
      createdAt: { lt: cutoff },
    },
  });
}