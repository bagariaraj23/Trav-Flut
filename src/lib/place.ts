import { prisma } from "@/lib/prisma";
import { cacheGetJson, cacheSetJson, cacheKeys } from "@/lib/cache";
import { rlKeyFromUserOrIp, rateLimit } from "@/lib/rateLimit";
import { MapboxPlacesAdapter } from "@/lib/mapProviders/mapbox";
import type { NormalizedPlace } from "@/lib/mapProviders/adapter";
import { PlaceType, PlaceSource } from '@prisma/client'; // Import enums

const placesProvider = new MapboxPlacesAdapter();

// Helper function
function mapPlaceType(mapboxType?: string): PlaceType {
  const type = mapboxType?.toLowerCase();
  switch (type) {
    case 'restaurant':
    case 'cafe':
      return PlaceType.FOOD;
    case 'hotel':
    case 'lodging':
      return PlaceType.STAY;
    case 'poi':
    case 'landmark':
      return PlaceType.POI;
    default:
      return PlaceType.OTHER;
  }
}

export async function searchPlaces(params: {
  q: string;
  lat?: number;
  lng?: number;
  limit?: number;
  userId?: string;
  ip?: string;
}) {
  const { q, lat, lng, limit = 10, userId, ip } = params;

  // 1. Rate limiting check
  const rl = await rateLimit(
    rlKeyFromUserOrIp(userId, ip, "places:search"),
    30,
    60
  );
  if (!rl.allowed) return [] as NormalizedPlace[];

  // 2. Try cache with fallback to Mapbox
  const key = cacheKeys.search(q, lat, lng, undefined, limit);
  const cached = await cacheGetJson<NormalizedPlace[]>(key);
  
  if (cached) {
    console.log(`[Cache] Hit for search query: ${q}`);
    return cached;
  }

  console.log(`[Cache] Miss for search query: ${q}`);
  
  // 4. If not in cache, call Mapbox
  const searchResults = await placesProvider.search({ q, lat, lng, limit });

  // 5. Cache results with TTL
  if (searchResults.length > 0) {
    await cacheSetJson(key, searchResults, 3600); // Cache for 1 hour
    console.log(`[Cache] Stored ${searchResults.length} results for query: ${q}`);
  }

  return searchResults;
}

export async function resolvePlace(input: {
  name: string;
  address?: string;
  lat: number;
  lng: number;
  externalId?: string;
  placeType?: string;
  source?: string;
}) {
  // Helper to convert Place to cache-safe object
  const serializePlace = (place: any) => ({
    ...place,
    createdAt: place.createdAt.toISOString(),
    updatedAt: place.updatedAt.toISOString()
  });

  // Helper to deserialize cached place
  const deserializePlace = (cached: any) => ({
    ...cached,
    createdAt: new Date(cached.createdAt),
    updatedAt: new Date(cached.updatedAt)
  });

  // 1. Try cache first for resolved places
  const cacheKey = input.externalId
    ? `place:${input.externalId}`
    : `place:${input.name}:${input.lat}:${input.lng}`;

  const cached = await cacheGetJson<{ placeId: string; place: any }>(cacheKey);
  if (cached) {
    console.log(`[Cache] Hit for place resolution: ${input.name}`);
    return { 
      placeId: cached.placeId, 
      place: deserializePlace(cached.place)
    };
  }

  // 2. If has externalId, try direct lookup
  if (input.externalId) {
    const existingByExt = await prisma.place.findUnique({
      where: { externalId: input.externalId },
    });
    if (existingByExt) {
      const serialized = {
        placeId: existingByExt.id,
        place: serializePlace(existingByExt)
      };
      await cacheSetJson(cacheKey, serialized, 86400); // Cache for 24 hours
      return {
        placeId: existingByExt.id,
        place: existingByExt
      };
    }
  }

  // 3. Try spatial deduplication
  const lat = input.lat;
  const lng = input.lng;
  const name = input.name.trim();
  const nearby = await prisma.place.findMany({
    where: {
      name: { equals: name, mode: "insensitive" },
      lat: { gte: lat - 0.00025, lte: lat + 0.00025 },
      lng: { gte: lng - 0.00025, lte: lng + 0.00025 },
    },
    take: 1,
  });

  if (nearby.length > 0) {
    const serialized = {
      placeId: nearby[0].id,
      place: serializePlace(nearby[0])
    };
    await cacheSetJson(cacheKey, serialized, 86400); // Cache for 24 hours
    return {
      placeId: nearby[0].id,
      place: nearby[0]
    };
  }

  // 4. Create new place if no match found
  const place = await prisma.place.create({
    data: {
      name,
      address: input.address,
      lat,
      lng,
      placeType: mapPlaceType(input.placeType),
      source: (input.source as PlaceSource) ?? PlaceSource.MAPBOX,
      externalId: input.externalId,
    },
  });
  return { placeId: place.id, place };
}

export async function attachPlaceToTrip(
  tripId: string,
  placeId: string,
  payload: {
    visitedAt?: Date;
    dayIndex?: number;
    notes?: string;
    createThreadEntry?: boolean;
    authorId?: string;
  }
) {
  const visitedAt = payload.visitedAt ?? null;
  const pot = await prisma.placeOnTrip.upsert({
    where: { tripId_placeId_visitedAt: { tripId, placeId, visitedAt: visitedAt ?? new Date() } },
    update: {},
    create: {
      tripId,
      placeId,
      visitedAt,
      dayIndex: payload.dayIndex ?? null,
      notes: payload.notes ?? null,
    },
  });

  if (payload.createThreadEntry && payload.authorId) {
    await prisma.tripThreadEntry.create({
      data: {
        tripId,
        authorId: payload.authorId,
        type: "LOCATION",
        contentText: payload.notes ?? null,
        placeId,
      },
    });
    await prisma.trip.update({
      where: { id: tripId },
      data: { entryCount: { increment: 1 } },
    });
  }

  return { placeOnTripId: pot.id, created: true };
}

export async function getTripPlaces(tripId: string) {
  const items = await prisma.placeOnTrip.findMany({
    where: { tripId },
    include: { place: true },
    orderBy: [{ visitedAt: "asc" }, { order: "asc" }],
  });
  return items;
}
