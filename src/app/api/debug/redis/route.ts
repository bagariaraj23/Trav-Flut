import { NextRequest, NextResponse } from "next/server";
import { diagnoseRedisConnection, testRedisCommand } from "@/lib/cache-debug";
import { resetUpstashRateLimit, getUpstashRateLimitStatus } from "@/lib/cache";

export const dynamic = "force-dynamic";

function productionLocked() {
  return NextResponse.json(
    { success: false, error: "Not found" },
    { status: 404 }
  );
}

export async function GET() {
  if (process.env.NODE_ENV === "production") {
    return productionLocked();
  }
  try {
    const diagnostics = await diagnoseRedisConnection();
    const testResult = await testRedisCommand();
    const rateLimitStatus = getUpstashRateLimitStatus();
    
    return NextResponse.json({
      success: true,
      diagnostics,
      testResult,
      rateLimitStatus: {
        ...rateLimitStatus,
        resetTime: rateLimitStatus.resetTime ? new Date(rateLimitStatus.resetTime).toISOString() : undefined,
        remainingMinutes: rateLimitStatus.remainingMs ? Math.round(rateLimitStatus.remainingMs / 60000) : undefined,
      },
    });
  } catch (error) {
    return NextResponse.json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }, { status: 500 });
  }
}

export async function POST(request: NextRequest) {
  if (process.env.NODE_ENV === "production") {
    return productionLocked();
  }
  try {
    const { action } = await request.json().catch(() => ({}));
    
    if (action === 'reset') {
      resetUpstashRateLimit();
      return NextResponse.json({
        success: true,
        message: "Rate limit flag reset",
      });
    }
    
    return NextResponse.json(
      { success: false, error: 'Invalid action. Use { "action": "reset" }' },
      { status: 400 }
    );
  } catch (error) {
    return NextResponse.json({
      success: false,
      error: error instanceof Error ? error.message : String(error),
    }, { status: 500 });
  }
}

