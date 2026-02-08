import { NextRequest, NextResponse } from "next/server";
import { resetWithToken } from "@/lib/services/passwordReset";
import { ZodError } from "zod";
import { withRateLimit, withLogging } from "@/lib/middleware";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "auth_reset", async (rateLimitedReq) => {
      try {
        const body = await rateLimitedReq.json().catch(() => ({}));
        await resetWithToken(body);

        const res = NextResponse.json({
          ok: true,
          message:
            "Your password has been successfully updated. You will be logged out of all devices.",
        });
        res.headers.set(
          "Cache-Control",
          "no-store, no-cache, must-revalidate, proxy-revalidate"
        );
        res.headers.set("Pragma", "no-cache");
        res.headers.set("Expires", "0");
        return res;
      } catch (error) {
        // Downgrade expected validation failures to warnings in logs
        const expectedMessages = new Set([
          "This reset link has already been used",
          "This reset link has expired",
          "Invalid reset token",
          "Invalid user account",
          "Current password is incorrect",
          "User account has no password set",
          "New password must be different from current password",
        ]);
        if (error instanceof Error && expectedMessages.has(error.message)) {
          console.warn("Password reset validation:", error.message);
        } else {
          console.error("Password reset error:", error);
        }

        if (error instanceof ZodError) {
          return NextResponse.json(
            {
              ok: false,
              message: "Invalid input",
              errors: error.errors,
            },
            { status: 400 }
          );
        }

        if (error instanceof Error) {
          // Handle specific error messages from resetWithToken
          if (error.message === "This reset link has already been used") {
            return NextResponse.json(
              {
                ok: false,
                message: error.message,
              },
              { status: 400 }
            );
          }

          if (error.message === "This reset link has expired") {
            return NextResponse.json(
              {
                ok: false,
                message: error.message,
              },
              { status: 400 }
            );
          }

          if (
            error.message === "Invalid reset token" ||
            error.message === "Invalid user account"
          ) {
            return NextResponse.json(
              {
                ok: false,
                message: "Invalid or expired reset link",
              },
              { status: 400 }
            );
          }

          if (error.message === "Current password is incorrect") {
            return NextResponse.json(
              {
                ok: false,
                message: "Current password is incorrect",
              },
              { status: 400 }
            );
          }

          if (error.message === "User account has no password set") {
            return NextResponse.json(
              {
                ok: false,
                message: "Account security issue. Please contact support.",
              },
              { status: 400 }
            );
          }

          if (
            error.message ===
            "New password must be different from current password"
          ) {
            return NextResponse.json(
              {
                ok: false,
                message: "New password must be different from current password",
              },
              { status: 400 }
            );
          }
        }

        // Generic error
        return NextResponse.json(
          {
            ok: false,
            message: "An error occurred while resetting your password",
          },
          { status: 500 }
        );
      }
    });
  });

  return await loggedHandler(request);
}
