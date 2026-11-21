import { NextRequest, NextResponse } from "next/server";
import { withLogging, withRateLimit } from "@/lib/middleware";
import { prisma } from "@/lib/prisma";
import { publicSupporterNames } from "@/lib/chipIn";

export async function GET(request: NextRequest) {
  const loggedHandler = withLogging(async (req) => {
    return withRateLimit(req, "chip_in_read", async () => {
      const rows = await prisma.chipIn.findMany({
        where: { status: "PAID", displayName: { not: null } },
        orderBy: { paidAt: "desc" },
        take: 60,
        select: { displayName: true },
      });
      return NextResponse.json({
        names: publicSupporterNames(rows.map((row) => row.displayName)),
      });
    });
  });
  return loggedHandler(request);
}
