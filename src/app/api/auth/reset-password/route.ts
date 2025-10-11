import { NextRequest } from "next/server";
import { resetWithToken } from "@/lib/services/passwordReset";
import { ZodError } from "zod";

export async function POST(req: NextRequest) {
  try {
    const body = await req.json().catch(() => ({}));
    await resetWithToken(body);
    
    return Response.json({
      ok: true,
      message: "Your password has been successfully updated."
    });
  } catch (error) {
    console.error('Password reset error:', error);
    
    if (error instanceof ZodError) {
      return Response.json({
        ok: false,
        message: "Invalid input",
        errors: error.errors
      }, { status: 400 });
    }

    if (error instanceof Error) {
      // Handle specific error messages from resetWithToken
      if (error.message === "This reset link has already been used") {
        return Response.json({
          ok: false,
          message: error.message
        }, { status: 400 });
      }
      
      if (error.message === "This reset link has expired") {
        return Response.json({
          ok: false,
          message: error.message
        }, { status: 400 });
      }
      
      if (error.message === "Invalid reset token" || error.message === "Invalid user account") {
        return Response.json({
          ok: false,
          message: "Invalid or expired reset link"
        }, { status: 400 });
      }
    }

    // Generic error
    return Response.json({
      ok: false,
      message: "An error occurred while resetting your password"
    }, { status: 500 });
  }
}