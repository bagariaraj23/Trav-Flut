import { NextRequest } from "next/server";
import { resetWithToken } from "@/lib/services/passwordReset";
import { ok } from "@/lib/response";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  await resetWithToken(body);
  return ok({ ok: true, message: "If the token was valid, your password has been updated." });
}