import { OAuth2Client } from "google-auth-library";

const clientId = process.env.GOOGLE_CLIENT_ID || "";

export interface GoogleTokenPayload {
  email: string;
  name?: string;
  picture?: string;
  sub: string;
}

const GOOGLE_VERIFY_TIMEOUT_MS = 2500;

export class GoogleVerifyTimeoutError extends Error {
  constructor() {
    super("Google token verification timed out");
    this.name = "GoogleVerifyTimeoutError";
  }
}

/**
 * Verify a Google ID token and return the payload (email, name, picture, sub).
 * Returns null if the token is invalid or expired.
 */
export async function verifyGoogleIdToken(
  idToken: string
): Promise<GoogleTokenPayload | null> {
  if (!clientId) {
    console.warn("[GoogleAuth] GOOGLE_CLIENT_ID is not set");
    return null;
  }
  try {
    const client = new OAuth2Client(clientId);
    let timer: ReturnType<typeof setTimeout> | undefined;
    let ticket;
    try {
      ticket = await Promise.race([
        client.verifyIdToken({
          idToken,
          audience: clientId,
        }),
        new Promise<never>((_, reject) => {
          timer = setTimeout(
            () => reject(new GoogleVerifyTimeoutError()),
            GOOGLE_VERIFY_TIMEOUT_MS
          );
        }),
      ]);
    } finally {
      if (timer) clearTimeout(timer);
    }
    const payload = ticket.getPayload();
    if (!payload || !payload.email) {
      return null;
    }
    return {
      email: payload.email,
      name: payload.name ?? undefined,
      picture: payload.picture ?? undefined,
      sub: payload.sub,
    };
  } catch (error) {
    if (error instanceof GoogleVerifyTimeoutError) {
      throw error;
    }
    console.error("[GoogleAuth] verifyIdToken error:", error);
    return null;
  }
}
