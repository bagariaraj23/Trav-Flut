import { prisma } from "@/lib/prisma";
import { Place, PlaceType, PlaceSource } from "@prisma/client";
import { MapboxPlacesAdapter } from "@/lib/mapProviders/mapbox";
import {
  cacheGetJson,
  cacheSetJson,
  bucketCoord,
  cacheDelete,
  upstashFetch,
} from "@/lib/cache";
import { rlKeyFromUserOrIp, rateLimit } from "@/lib/rateLimit";
import { withLock } from "@/lib/mutex";

const placesProvider = new MapboxPlacesAdapter();

// Constants for spatial matching
const SPATIAL_PRECISION = {
  CITY: 2, // ~1.1km
  DISTRICT: 3, // ~110m
  POI: 4, // ~11m
};

const MATCH_THRESHOLD = {
  CITY: 0.03, // ~3.3km
  DISTRICT: 0.01, // ~1.1km
  POI: 0.001, // ~110m
};

// Levenshtein distance for fuzzy name matching
function levenshtein(a: string, b: string): number {
  if (a.length === 0) return b.length;
  if (b.length === 0) return a.length;

  const matrix = Array(b.length + 1)
    .fill(null)
    .map(() => Array(a.length + 1).fill(null));

  for (let i = 0; i <= a.length; i++) matrix[0][i] = i;
  for (let j = 0; j <= b.length; j++) matrix[j][0] = j;

  for (let j = 1; j <= b.length; j++) {
    for (let i = 1; i <= a.length; i++) {
      const substitutionCost = a[i - 1] === b[j - 1] ? 0 : 1;
      matrix[j][i] = Math.min(
        matrix[j][i - 1] + 1,
        matrix[j - 1][i] + 1,
        matrix[j - 1][i - 1] + substitutionCost
      );
    }
  }

  return matrix[b.length][a.length];
}

// Normalized string similarity (0-1)
function stringSimilarity(a: string, b: string): number {
  const maxLen = Math.max(a.length, b.length);
  if (maxLen === 0) return 1;
  return 1 - levenshtein(a.toLowerCase(), b.toLowerCase()) / maxLen;
}

export interface PlaceInput {
  name: string;
  address?: string;
  lat: number;
  lng: number;
  externalId?: string;
  placeType?: string;
  source?: string;
}

// Get appropriate precision and threshold based on place type
function getPlaceMetrics(placeType?: string): {
  precision: number;
  threshold: number;
} {
  switch (placeType?.toUpperCase()) {
    case "CITY":
    case "REGION":
    case "COUNTRY":
      return {
        precision: SPATIAL_PRECISION.CITY,
        threshold: MATCH_THRESHOLD.CITY,
      };
    case "DISTRICT":
    case "LOCALITY":
    case "NEIGHBORHOOD":
      return {
        precision: SPATIAL_PRECISION.DISTRICT,
        threshold: MATCH_THRESHOLD.DISTRICT,
      };
    default:
      return {
        precision: SPATIAL_PRECISION.POI,
        threshold: MATCH_THRESHOLD.POI,
      };
  }
}

// Helper to generate a spatial hash for deduplication
function generateSpatialKey(
  lat: number,
  lng: number,
  placeType?: string
): string {
  const { precision } = getPlaceMetrics(placeType);
  // Convert coordinates to base32 strings with precision
  const factor = Math.pow(10, precision);
  const bucketLat = Math.round(lat * factor) / factor;
  const bucketLng = Math.round(lng * factor) / factor;
  return `${bucketLat}:${bucketLng}`;
}

// Helper to convert Place to cache-safe object
export function serializePlace(place: any) {
  return {
    ...place,
    createdAt: place.createdAt.toISOString(),
    updatedAt: place.updatedAt.toISOString(),
  };
}

// Helper to deserialize cached place
function deserializePlace(cached: any) {
  return {
    ...cached,
    createdAt: new Date(cached.createdAt),
    updatedAt: new Date(cached.updatedAt),
  };
}

// Normalize placeType from Mapbox values to valid Prisma enum values
function normalizePlaceType(placeType?: string): PlaceType {
  if (!placeType) return "POI";

  const upperType = placeType.toUpperCase();

  // Mapbox returns CITY, DISTRICT, etc. but Prisma only accepts:
  // POI, STAY, FOOD, TRANSPORT, VIEWPOINT, OTHER
  if (
    upperType === "CITY" ||
    upperType === "REGION" ||
    upperType === "COUNTRY"
  ) {
    return "OTHER";
  }

  if (
    upperType === "DISTRICT" ||
    upperType === "LOCALITY" ||
    upperType === "NEIGHBORHOOD"
  ) {
    return "OTHER";
  }

  // Try to cast directly, fallback to POI if invalid
  const validTypes: PlaceType[] = [
    "POI",
    "STAY",
    "FOOD",
    "TRANSPORT",
    "VIEWPOINT",
    "OTHER",
  ];
  if (validTypes.includes(upperType as PlaceType)) {
    return upperType as PlaceType;
  }

  return "POI";
}

// Function to check if two places should be considered the same
function arePlacesClose(
  p1: { lat: number; lng: number; name: string; placeType?: string },
  p2: { lat: number; lng: number; name: string; placeType?: string }
): boolean {
  const { threshold } = getPlaceMetrics(p1.placeType || p2.placeType);
  const spatiallyClose =
    Math.abs(p1.lat - p2.lat) <= threshold &&
    Math.abs(p1.lng - p2.lng) <= threshold;

  // For POIs, require both spatial and name similarity
  if (!(p1.placeType === "CITY" || p2.placeType === "CITY")) {
    return spatiallyClose && stringSimilarity(p1.name, p2.name) >= 0.7;
  }

  // For cities, either high spatial similarity or high name similarity
  return spatiallyClose || stringSimilarity(p1.name, p2.name) >= 0.8;
}

// Main search function
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
    20,
    60
  );
  if (!rl.allowed) {
    throw new Error("Rate limit exceeded");
  }

  // Basic normalization for cache key
  const queryForCache = q.trim().replace(/\s+/g, " ");

  // More aggressive normalization for search
  const normalizedQuery = queryForCache
    .toLowerCase()
    .normalize("NFKD")
    .replace(/[\u0300-\u036f]/g, "") // remove diacritics
    .replace(/[^\w\s-]/g, ""); // remove special chars except spaces and hyphens

  // Human-readable, debuggable cache key
  const searchKey = `plc:srch:${encodeURIComponent(queryForCache)}:${lat ? bucketCoord(lat) : "null"
    }:${lng ? bucketCoord(lng) : "null"}:${limit}`;

  // 2. Try cache first
  const cached = await cacheGetJson<Place[]>(searchKey);
  if (cached) {
    console.log(`[Cache] Hit for search: ${normalizedQuery}`);
    return cached;
  }

  // 3. Try local database for existing matches
  const localResults = await prisma.place.findMany({
    where: {
      OR: [
        { name: { contains: normalizedQuery, mode: "insensitive" } },
        { address: { contains: normalizedQuery, mode: "insensitive" } },
      ],
    },
    orderBy: [{ name: "asc" }],
    take: limit,
  });

  if (localResults.length > 0) {
    console.log(`[DB] Found ${localResults.length} local matches for: ${q}`);
    // Cache local results
    await cacheSetJson(searchKey, localResults.map(serializePlace), 300);
    return localResults;
  }

  // 4. Cache miss - search external API
  console.log(`[Cache] Miss for search: ${q}`);
  const results = await placesProvider.search({ q, lat, lng, limit });

  // Early return if no results
  if (results.length === 0) {
    console.log("[Mapbox] No results found");
    // Cache empty result to prevent repeated API calls
    await cacheSetJson(searchKey, [], 300);
    return [];
  }

  // Deduplicate results using spatial indexing
  const deduplicatedResults: Place[] = [];
  const seen = new Set<string>();

  // Calculate bounding box with proper thresholds
  let minLat = Infinity,
    maxLat = -Infinity,
    minLng = Infinity,
    maxLng = -Infinity;
  for (const p of results) {
    const { threshold } = getPlaceMetrics(p.placeType);
    minLat = Math.min(minLat, p.lat - threshold);
    maxLat = Math.max(maxLat, p.lat + threshold);
    minLng = Math.min(minLng, p.lng - threshold);
    maxLng = Math.max(maxLng, p.lng + threshold);
  }

  // Single batch query for potential matches
  const dbCandidates = await prisma.place.findMany({
    where: {
      AND: [
        { lat: { gte: minLat, lte: maxLat } },
        { lng: { gte: minLng, lte: maxLng } },
      ],
    },
  });

  // Build spatial index for efficient lookup
  const spatialIndex = new Map<string, Place[]>();
  for (const dbPlace of dbCandidates) {
    const keys = [
      generateSpatialKey(dbPlace.lat, dbPlace.lng, dbPlace.placeType),
      generateSpatialKey(dbPlace.lat, dbPlace.lng, "CITY"), // Index at city level too for fuzzy matching
    ];

    for (const key of keys) {
      if (!spatialIndex.has(key)) {
        spatialIndex.set(key, []);
      }
      spatialIndex.get(key)!.push(dbPlace);
    }
  }

  const newPlacesToCreate: Array<{
    name: string;
    address?: string;
    lat: number;
    lng: number;
    externalId?: string;
    placeType: PlaceType;
    source: PlaceSource;
  }> = [];

  // Process mapbox results with optimized matching
  for (const place of results) {
    const spatialKey = generateSpatialKey(
      place.lat,
      place.lng,
      place.placeType
    );
    let isDuplicate = false;

    // Check nearby spatial buckets for matches
    const nearbyBuckets = [
      spatialKey,
      generateSpatialKey(place.lat, place.lng, "CITY"),
    ];

    for (const bucket of nearbyBuckets) {
      const candidates = spatialIndex.get(bucket) || [];
      for (const dbPlace of candidates) {
        if (
          arePlacesClose(
            { ...place, name: place.name },
            { ...dbPlace, name: dbPlace.name, placeType: dbPlace.placeType }
          )
        ) {
          isDuplicate = true;
          if (!seen.has(dbPlace.id)) {
            deduplicatedResults.push(dbPlace);
            seen.add(dbPlace.id);
          }
          break;
        }
      }
      if (isDuplicate) break;
    }

    if (!isDuplicate) {
      // Collect for batch creation
      newPlacesToCreate.push({
        name: place.name,
        address: place.address,
        lat: place.lat,
        lng: place.lng,
        externalId: place.externalId,
        placeType: normalizePlaceType(place.placeType),
        source: (place.source as PlaceSource) ?? "MAPBOX",
      });
    }
  }

  // Batch create all new places with deduplication by externalId
  if (newPlacesToCreate.length > 0) {
    // Deduplicate by externalId before creating
    const uniqueByExternalId = new Map<string, (typeof newPlacesToCreate)[0]>();
    const withoutExternalId: typeof newPlacesToCreate = [];

    for (const place of newPlacesToCreate) {
      if (place.externalId) {
        // Only keep first occurrence of each externalId
        if (!uniqueByExternalId.has(place.externalId)) {
          uniqueByExternalId.set(place.externalId, place);
        }
      } else {
        withoutExternalId.push(place);
      }
    }

    const uniquePlaces = [
      ...Array.from(uniqueByExternalId.values()),
      ...withoutExternalId,
    ];

    console.log(
      `[DB] Creating ${uniquePlaces.length} new places (deduped from ${newPlacesToCreate.length})`
    );

    // Use upsert for places with externalId to handle race conditions
    const createdPlaces: Place[] = [];

    for (const data of uniquePlaces) {
      try {
        if (data.externalId) {
          // Use upsert to handle concurrent creation attempts
          const place = await prisma.place.upsert({
            where: { externalId: data.externalId },
            update: {}, // Don't update if exists
            create: data,
          });
          createdPlaces.push(place);
        } else {
          // For places without externalId, use regular create
          const place = await prisma.place.create({ data });
          createdPlaces.push(place);
        }
      } catch (error: any) {
        // Handle unique constraint violation (P2002)
        if (error.code === "P2002" && data.externalId) {
          // Place already exists, fetch it
          const existing = await prisma.place.findUnique({
            where: { externalId: data.externalId },
          });
          if (existing) {
            createdPlaces.push(existing);
          }
        } else {
          console.error(`[DB] Error creating place ${data.name}:`, error);
          // Continue with other places
        }
      }
    }

    for (const newPlace of createdPlaces) {
      if (!seen.has(newPlace.id)) {
        deduplicatedResults.push(newPlace);
        seen.add(newPlace.id);
      }
    }
  }

  // Cache deduplicated results
  if (deduplicatedResults.length > 0) {
    await cacheSetJson(searchKey, deduplicatedResults.map(serializePlace), 300);
  }

  return deduplicatedResults;
}

// Main resolve function
export async function resolvePlace(input: PlaceInput) {
  const spatialKey = generateSpatialKey(input.lat, input.lng);

  // Generate reference cache keys
  const cacheKeys = [
    input.externalId ? `place:ext:${input.externalId}` : null,
    `place:spatial:${spatialKey}`,
    `place:name:${input.name.toLowerCase()}:${spatialKey}`,
  ].filter(Boolean) as string[];

  // 1. Try cache first with two-step lookup
  for (const key of cacheKeys) {
    // First lookup: get the primary key reference
    const ref = await cacheGetJson<string>(key);

    if (ref && typeof ref === "string" && ref.length > 0) {
      const cachedPlace = await cacheGetJson<any>(`place:${ref}`);
      if (cachedPlace) {
        console.log(`[Cache] Hit for key: ${key} -> place:${ref}`);
        return deserializePlace(cachedPlace);
      } else {
        // Reference exists but data missing - clean up the dangling reference
        console.warn(`[Cache] Dangling reference at ${key}, cleaning up`);
        await cacheDelete(key);
      }
    }
  }

  // 2. Try database with mutex to prevent duplicates
  return await withLock(`place:resolve:${spatialKey}`, async () => {
    // Check external ID first
    if (input.externalId) {
      const existing = await prisma.place.findUnique({
        where: { externalId: input.externalId },
      });
      if (existing) {
        await cacheResults(existing, cacheKeys);
        return existing;
      }
    }

    // Try spatial match with dynamic threshold
    const { threshold } = getPlaceMetrics(input.placeType);
    const spatialMatches = await prisma.place.findMany({
      where: {
        AND: [
          // Don't filter by exact name here - we'll use fuzzy matching after
          {
            lat: { gte: input.lat - threshold, lte: input.lat + threshold },
            lng: { gte: input.lng - threshold, lte: input.lng + threshold },
          },
        ],
      },
    });

    // Find closest match if any
    const match = spatialMatches.find((p) => arePlacesClose(p, input));
    if (match) {
      await cacheResults(match, cacheKeys);
      return match;
    }

    // No match found - create new place (use upsert if externalId exists)
    const placeData = {
      name: input.name,
      address: input.address,
      lat: input.lat,
      lng: input.lng,
      externalId: input.externalId,
      placeType: normalizePlaceType(input.placeType),
      source: (input.source as PlaceSource) ?? "USER",
    };

    const created = input.externalId
      ? await prisma.place.upsert({
        where: { externalId: input.externalId },
        update: {}, // Don't update if exists
        create: placeData,
      })
      : await prisma.place.create({ data: placeData });

    await cacheResults(created, cacheKeys);
    return created;
  });
}

// Helper to cache place with storage optimization using pipelining
async function cacheResults(place: Place, keys: string[]) {
  const spatialKey = generateSpatialKey(place.lat, place.lng, place.placeType);
  const serializedPlace = serializePlace(place);

  // Build pipeline manually for full control
  const pipeline: [string, ...string[]][] = [];

  // 1. Store full place data at primary key
  pipeline.push([
    "setex",
    `place:${place.id}`,
    "3600",
    JSON.stringify(serializedPlace),
  ]);

  // 2. Store reference at external ID key
  if (place.externalId) {
    pipeline.push(["setex", `place:ext:${place.externalId}`, "3600", place.id]);
  }

  // 3. Store reference at spatial key
  pipeline.push(["setex", `place:spatial:${spatialKey}`, "3600", place.id]);

  // 4. Store reference at name+spatial key
  pipeline.push([
    "setex",
    `place:name:${place.name.toLowerCase()}:${spatialKey}`,
    "3600",
    place.id,
  ]);

  // Execute pipeline with error handling
  try {
    const result = await upstashFetch("pipeline", pipeline);
    if (!result) {
      console.warn(
        `[Cache] Pipeline failed for place ${place.id} - Redis unavailable`
      );
    } else {
      console.log(
        `[Cache] ✓ Stored place ${place.id} (${pipeline.length} commands)`
      );
    }
  } catch (error) {
    console.error(`[Cache] Pipeline error for place ${place.id}:`, error);
  }
}

// Cache invalidation helper
export async function invalidatePlaceCache(place: {
  id: string;
  externalId?: string;
}) {
  const keys = [
    `place:${place.id}`,
    place.externalId ? `place:external:${place.externalId}` : null,
    // Could add more keys based on name/spatial location if needed
  ].filter(Boolean) as string[];

  for (const key of keys) {
    await cacheDelete(key);
  }
}

// Additional helper functions
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
  const now = new Date();
  const visitedAt = payload.visitedAt ?? now;
  const pot = await prisma.placeOnTrip.upsert({
    where: { tripId_placeId_visitedAt: { tripId, placeId, visitedAt } },
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
