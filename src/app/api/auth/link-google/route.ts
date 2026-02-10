import { NextRequest, NextResponse } from "next/server";
import { prisma } from "@/lib/prisma";
import { verifyGoogleIdToken } from "@/lib/services/googleAuth";
import { authGoogleSchema } from "@/lib/validation";
import { ApiResponse } from "@/types/api";
import { withRateLimit, withAuth, withLogging } from "@/lib/middleware";
import { OAuthProvider } from "@prisma/client";

export async function POST(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "auth_link_google", async (rateLimitedReq) => {
      return withAuth(rateLimitedReq, async (authenticatedReq) => {
        try {
          const currentUserId = authenticatedReq.user!.userId;
          const body = await authenticatedReq.json();
          const validatedData = authGoogleSchema.parse(body);
          const { idToken } = validatedData;

          const payload = await verifyGoogleIdToken(idToken);
          if (!payload) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Invalid Google token" },
              { status: 401 }
            );
          }

          const sub = payload.sub;
          const googleEmail = payload.email.toLowerCase().trim();

          const currentUser = await prisma.user.findUnique({
            where: { id: currentUserId },
            include: { oauthAccounts: true },
          });
          if (!currentUser) {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "User not found" },
              { status: 404 }
            );
          }

          const existingOAuth = await prisma.oAuthAccount.findUnique({
            where: {
              provider_providerUserId: {
                provider: OAuthProvider.GOOGLE,
                providerUserId: sub,
              },
            },
            include: { user: true },
          });

          if (existingOAuth && existingOAuth.userId !== currentUserId) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error: "This Google account is already linked to another account.",
              },
              { status: 400 }
            );
          }

          if (existingOAuth && existingOAuth.userId === currentUserId) {
            return NextResponse.json<ApiResponse>({
              success: true,
              data: null,
              message: "Already linked.",
            });
          }

          if (googleEmail !== currentUser.email.toLowerCase()) {
            return NextResponse.json<ApiResponse>(
              {
                success: false,
                error:
                  "This Google account's email does not match your account. Use a Google account with the same email.",
              },
              { status: 400 }
            );
          }

          await prisma.oAuthAccount.create({
            data: {
              userId: currentUserId,
              provider: OAuthProvider.GOOGLE,
              providerUserId: sub,
            },
          });

          return NextResponse.json<ApiResponse>({
            success: true,
            data: null,
            message: "Google account linked successfully.",
          });
        } catch (error: unknown) {
          if (error && typeof error === "object" && "name" in error && (error as { name: string }).name === "ZodError") {
            return NextResponse.json<ApiResponse>(
              { success: false, error: "Validation error" },
              { status: 400 }
            );
          }
          console.error("[API] POST /auth/link-google error:", error);
          return NextResponse.json<ApiResponse>(
            { success: false, error: "Internal server error" },
            { status: 500 }
          );
        }
      });
    });
  });
  return await loggedHandler(request);
}
