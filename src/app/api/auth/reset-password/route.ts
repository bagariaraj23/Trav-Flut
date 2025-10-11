import { NextRequest } from "next/server";
import { resetWithToken } from "@/lib/services/passwordReset";

export async function POST(req: NextRequest) {
  const body = await req.json().catch(() => ({}));
  console.log(`BOSY: ${JSON.stringify(body)}`);
  await resetWithToken(body);
  return Response.json({
    ok: true,
    message: "If the token was valid, your password has been updated."
  });
}