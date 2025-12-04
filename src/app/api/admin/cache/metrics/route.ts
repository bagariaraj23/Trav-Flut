import { NextRequest, NextResponse } from 'next/server';
import { withAuth, AuthenticatedRequest } from '@/lib/middleware';
import { getCacheMetrics, resetCacheMetrics } from '@/lib/cache';

export const dynamic = 'force-dynamic';

export async function GET(request: NextRequest) {
  return withAuth(request, async (authenticatedReq: AuthenticatedRequest) => {
    try {
      const metrics = getCacheMetrics();
      
      return NextResponse.json({
        success: true,
        metrics: {
          ...metrics,
          redisHitRate: (metrics.redisHitRate * 100).toFixed(2) + '%',
          memoryHitRate: (metrics.memoryHitRate * 100).toFixed(2) + '%',
          overallHitRate: (metrics.overallHitRate * 100).toFixed(2) + '%',
        },
        uptime: {
          seconds: Math.floor((Date.now() - metrics.lastReset) / 1000),
          minutes: Math.floor((Date.now() - metrics.lastReset) / 60000),
          hours: Math.floor((Date.now() - metrics.lastReset) / 3600000),
        },
      });
    } catch (error) {
      console.error('[Cache Metrics] Error:', error);
      return NextResponse.json(
        {
          success: false,
          error: error instanceof Error ? error.message : 'Unknown error',
        },
        { status: 500 }
      );
    }
  });
}

export async function POST(request: NextRequest) {
  return withAuth(request, async (authenticatedReq: AuthenticatedRequest) => {
    try {
      const { action } = await authenticatedReq.json().catch(() => ({}));
      
      if (action === 'reset') {
        resetCacheMetrics();
        return NextResponse.json({
          success: true,
          message: 'Cache metrics reset successfully',
        });
      }
      
      return NextResponse.json(
        { success: false, error: 'Invalid action. Use { "action": "reset" }' },
        { status: 400 }
      );
    } catch (error) {
      console.error('[Cache Metrics] Error:', error);
      return NextResponse.json(
        {
          success: false,
          error: error instanceof Error ? error.message : 'Unknown error',
        },
        { status: 500 }
      );
    }
  });
}

