import { NextRequest, NextResponse } from "next/server";
import { validateResetToken } from "@/lib/services/passwordReset";
import { z } from "zod";
import { withRateLimit, withLogging } from "@/lib/middleware";

const validateSchema = z.object({
  token: z.string().min(16),
  email: z.string().email(),
  allowUsed: z.boolean().optional().default(false),
});

export async function POST(request: NextRequest) {
  return withLogging(async (req) => {
    return withRateLimit(req, "auth_validate", async (rateLimitedReq) => {
      try {
        const body = await rateLimitedReq.json();
        const { token, email, allowUsed } = validateSchema.parse(body);

        const result = await validateResetToken(
          token,
          email,
          allowUsed ?? false
        );

        if (!result.valid) {
          return NextResponse.json(
            {
              valid: false,
              error: result.error || "unknown-error",
              message: getErrorMessage(result.error || "unknown-error"),
            },
            { status: 400 }
          );
        }

        return NextResponse.json({ valid: true });
      } catch (error) {
        console.error("Error validating reset token:", error);
        return NextResponse.json(
          {
            valid: false,
            error: "validation-error",
            message: "An error occurred while validating the reset token.",
          },
          { status: 500 }
        );
      }
    });
  });
}

function getErrorMessage(error: string): string {
  const errorMessages: Record<string, string> = {
    "invalid-token": "This password reset link is invalid.",
    "email-mismatch": "The email does not match the reset token.",
    "account-deleted": "This account has been deleted.",
    "token-used": "This password reset link has already been used.",
    "token-expired": "This password reset link has expired.",
    "validation-error": "An error occurred while validating the reset token.",
  };

  return errorMessages[error] || "An unknown error occurred.";
}
