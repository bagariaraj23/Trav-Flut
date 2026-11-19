import { GoogleAuth } from "google-auth-library";

const SCOPE = "https://www.googleapis.com/auth/cloud-platform";

export type FirebaseTesterResult = "added" | "skipped" | "failed";

function serviceAccount(): Record<string, unknown> | null {
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return null;
  try {
    const parsed = JSON.parse(raw) as Record<string, unknown>;
    if (typeof parsed.client_email !== "string" || typeof parsed.private_key !== "string") {
      return null;
    }
    return parsed;
  } catch {
    return null;
  }
}

/**
 * Adds an Android tester to a Firebase App Distribution group.
 * Firebase emails the tester a download link when this succeeds.
 * Missing configuration leaves the signup stored and skips the call.
 */
export async function addAndroidTester(email: string): Promise<FirebaseTesterResult> {
  const project = process.env.FIREBASE_PROJECT_NUMBER?.trim();
  const group = process.env.FIREBASE_TESTER_GROUP?.trim();
  const credentials = serviceAccount();
  if (!project || !group || !credentials) return "skipped";

  try {
    const auth = new GoogleAuth({
      credentials,
      scopes: [SCOPE],
    });
    const client = await auth.getClient();
    const token = await client.getAccessToken();
    if (!token.token) return "failed";

    const resource = `projects/${encodeURIComponent(project)}/groups/${encodeURIComponent(group)}`;
    const response = await fetch(
      `https://firebaseappdistribution.googleapis.com/v1/${resource}:batchJoin`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token.token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          emails: [email],
          createMissingTesters: true,
        }),
      }
    );
    return response.ok ? "added" : "failed";
  } catch {
    return "failed";
  }
}
