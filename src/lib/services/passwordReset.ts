import crypto from "crypto";
import { prisma } from "@/lib/prisma";
import { buildPasswordResetLink } from "@/lib/deeplink";
import {
  sendPasswordResetEmail,
  sendSecurityEmail,
} from "@/lib/services/email";
import { recordSecurityEvent } from "@/lib/services/securityEvent";
import { revokeAllRefreshTokens } from "@/lib/services/token";
import { passwordPolicy } from "@/lib/password-policy";
import { z } from "zod";
import bcrypt from "bcryptjs";
import config from "@/config/env";
import { safeLog } from "@/lib/utils/sanitize";

const TTL_MIN = config.passwordResetTtlMinutes;
const RESET_RETENTION_DAYS = Number(process.env.RESET_RETENTION_DAYS || 7);

const forgotSchema = z.object({ email: z.string().email() });
const resetSchema = z.object({
  token: z.string().min(16),
  currentPassword: z.string().min(1, "Current password is required"),
  newPassword: passwordPolicy,
});

export async function requestReset(
  payload: unknown,
  ctx?: { ip?: string; userAgent?: string },
  hooks?: { onToken?: (token: string) => void }
) {
  try {
    safeLog("Starting password reset request with payload:", payload);

    const { email } = forgotSchema.parse(payload);
    console.log("Looking up user with email:", email);

    const user = await prisma.user.findUnique({
      where: { email },
      select: {
        id: true,
        email: true,
        deletedAt: true,
      },
    });

    console.log("User lookup result:", user);

    if (!user) {
      console.log("No user found with email:", email);
      return;
    }

    if (user.deletedAt) {
      console.log("User account is deleted:", email);
      return;
    }

    console.log("Generating reset token for user:", user.id);
    const rawToken = crypto.randomBytes(48).toString("base64url");
    const tokenHash = crypto.createHash("sha256").update(rawToken).digest();
    hooks?.onToken?.(rawToken);
    const expiresAt = new Date(Date.now() + TTL_MIN * 60 * 1000);

    // Invalidate all previous unused reset tokens for this user
    console.log("Invalidating previous unused reset tokens");
    await prisma.passwordReset.updateMany({
      where: {
        userId: user.id,
        usedAt: null, // Only invalidate unused tokens
      },
      data: {
        usedAt: new Date(), // Mark as used to invalidate
      },
    });

    // Create the new password reset entry
    console.log("Creating password reset entry");
    await prisma.passwordReset.create({
      data: {
        userId: user.id,
        tokenHash,
        expiresAt,
        createdIp: ctx?.ip || null,
        userAgent: ctx?.userAgent || null,
      },
    });

    const { webUrl } = buildPasswordResetLink(rawToken, user.email);
    await sendPasswordResetEmail({
      to: user.email,
      resetLink: webUrl,
      ttlMinutes: TTL_MIN,
    });
    await recordSecurityEvent({
      userId: user.id,
      type: "PASSWORD_RESET_REQUESTED",
    });
  } catch (error) {
    console.error("Error in requestReset:", error);
    throw error;
  }
}

export async function resetWithToken(payload: unknown) {
  const { token, currentPassword, newPassword } = resetSchema.parse(payload);
  const tokenHash = crypto.createHash("sha256").update(token).digest();

  // Use a transaction with raw SQL for SELECT FOR UPDATE to prevent race conditions
  const result = await prisma.$transaction(async (tx) => {
    // Use raw SQL with SELECT FOR UPDATE to lock the row atomically
    const resetResult = await tx.$queryRaw<
      Array<{
        id: string;
        userId: string;
        tokenHash: Buffer;
        expiresAt: Date;
        usedAt: Date | null;
        createdIp: string | null;
        userAgent: string | null;
      }>
    >`
      SELECT id, "userId", "tokenHash", "expiresAt", "usedAt", "createdIp", "userAgent"
      FROM password_resets 
      WHERE "tokenHash" = ${tokenHash}
      FOR UPDATE
    `;

    if (resetResult.length === 0) {
      throw new Error("Invalid reset token");
    }

    const reset = resetResult[0];

    // Check if already used (this is now atomic within the locked transaction)
    if (reset.usedAt) {
      throw new Error("This reset link has already been used");
    }

    if (reset.expiresAt < new Date()) {
      throw new Error("This reset link has expired");
    }

    const user = await tx.user.findUnique({ where: { id: reset.userId } });
    if (!user || (user as any).deletedAt) {
      throw new Error("Invalid user account");
    }

    // Validate current password
    if (!user.password) {
      throw new Error("User account has no password set");
    }

    const isCurrentPasswordValid = await bcrypt.compare(
      currentPassword,
      user.password
    );
    if (!isCurrentPasswordValid) {
      throw new Error("Current password is incorrect");
    }

    // Check if new password is different from current password
    const isSamePassword = await bcrypt.compare(newPassword, user.password);
    if (isSamePassword) {
      throw new Error("New password must be different from current password");
    }

    const pwHash = await bcrypt.hash(newPassword, config.bcryptRounds);

    // Mark token as used FIRST to prevent race conditions
    await tx.passwordReset.update({
      where: { id: reset.id },
      data: { usedAt: new Date() },
    });

    // Then update the password
    await tx.user.update({
      where: { id: user.id },
      data: { password: pwHash },
    });

    return { user, reset };
  });

  const { user, reset } = result;

  // Revoke all refresh tokens for security
  await revokeAllRefreshTokens(user.id);

  // Record security events and send email
  await Promise.all([
    recordSecurityEvent({
      userId: user.id,
      type: "PASSWORD_RESET_SUCCESS",
      meta: {
        resetMethod: "token",
        ipAddress: reset.createdIp,
        userAgent: reset.userAgent,
      },
    }),
    recordSecurityEvent({
      userId: user.id,
      type: "PASSWORD_CHANGED",
      meta: {
        changeMethod: "reset",
        ipAddress: reset.createdIp,
      },
    }),
    sendSecurityEmail({ to: user.email }),
  ]);
}

export async function validateResetToken(
  token: string,
  email: string,
  allowUsed: boolean = false
) {
  try {
    const tokenHash = crypto.createHash("sha256").update(token).digest();

    const reset = await prisma.passwordReset.findUnique({
      where: { tokenHash },
      include: { user: { select: { email: true, deletedAt: true } } },
    });

    if (!reset) {
      return { valid: false, error: "invalid-token" };
    }

    if (reset.user.email !== email) {
      return { valid: false, error: "email-mismatch" };
    }

    if (reset.user.deletedAt) {
      return { valid: false, error: "account-deleted" };
    }

    // Only check for used tokens if allowUsed is false (for forgot-password page)
    if (!allowUsed && reset.usedAt) {
      return { valid: false, error: "token-used" };
    }

    if (reset.expiresAt < new Date()) {
      return { valid: false, error: "token-expired" };
    }

    return { valid: true };
  } catch (error) {
    console.error("Error validating reset token:", error);
    return { valid: false, error: "validation-error" };
  }
}

export async function cleanupExpiredResets() {
  const cutoff = new Date(
    Date.now() - RESET_RETENTION_DAYS * 24 * 60 * 60 * 1000
  );
  await prisma.passwordReset.deleteMany({
    where: {
      OR: [{ usedAt: { not: null } }, { expiresAt: { lt: new Date() } }],
      createdAt: { lt: cutoff },
    },
  });
}
