import { NextRequest, NextResponse } from "next/server";
import { withLogging, withRateLimit } from "@/lib/middleware";
import { syncCapturedChipIn } from "@/lib/services/chipInPayment";

export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "chip_in_status", async () => {
      const orderId = req.nextUrl.searchParams.get("orderId")?.trim() ?? "";
      const status = await syncCapturedChipIn(orderId);
      if (status === "missing") {
        return NextResponse.json({ error: "That chip-in was not found." }, { status: 404 });
      }
      return NextResponse.json({ status });
    });
  });
  return loggedHandler(request);
}
