import { NextRequest, NextResponse } from 'next/server';
import { withAuth, AuthenticatedRequest } from '@/lib/middleware';
import { warmPlaceCache, getPopularPlaces } from '@/lib/place';

export const dynamic = 'force-dynamic';

export async function POST(request: NextRequest) {
  return withAuth(request, async (authenticatedReq: AuthenticatedRequest) => {
    try {
      const { searchParams } = new URL(authenticatedReq.url);
      const limitParam = searchParams.get('limit');
      const limit = limitParam ? Math.min(parseInt(limitParam, 10), 500) : 100;

      if (isNaN(limit) || limit < 1) {
        return NextResponse.json(
          { success: false, error: 'Invalid limit parameter' },
          { status: 400 }
        );
      }

      const warmed = await warmPlaceCache(limit);
      const popularPlaces = await getPopularPlaces(limit);

      return NextResponse.json({
        success: true,
        warmed,
        total: popularPlaces.length,
        limit,
        message: `Successfully warmed cache for ${warmed} places`,
      });
    } catch (error) {
      console.error('[Cache Warm] Error:', error);
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

export async function GET(request: NextRequest) {
  return withAuth(request, async (authenticatedReq: AuthenticatedRequest) => {
    try {
      const { searchParams } = new URL(authenticatedReq.url);
      const limitParam = searchParams.get('limit');
      const limit = limitParam ? Math.min(parseInt(limitParam, 10), 500) : 100;

      if (isNaN(limit) || limit < 1) {
        return NextResponse.json(
          { success: false, error: 'Invalid limit parameter' },
          { status: 400 }
        );
      }

      const popularPlaces = await getPopularPlaces(limit);

      return NextResponse.json({
        success: true,
        count: popularPlaces.length,
        limit,
        places: popularPlaces.map(p => ({
          id: p.id,
          name: p.name,
          address: p.address,
          lat: p.lat,
          lng: p.lng,
          placeType: p.placeType,
          source: p.source,
        })),
      });
    } catch (error) {
      console.error('[Cache Warm] Error:', error);
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

