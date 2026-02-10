import { OAuth2Client } from "google-auth-library";

const clientId = process.env.GOOGLE_CLIENT_ID || "";

export interface GoogleTokenPayload {
  email: string;
  name?: string;
  picture?: string;
  sub: string;
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
    const ticket = await client.verifyIdToken({
      idToken,
      audience: clientId,
    });
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
    console.error("[GoogleAuth] verifyIdToken error:", error);
    return null;
  }
}
