import { prisma } from "@/lib/prisma";
import { Prisma, ThreadEntryType } from "@prisma/client";

/**
 * Soft cap for in-card swipeable thread snippets per trip.
 * Bounds DB payload for long trips while keeping a swipeable strip.
 */
export const FEED_THREAD_PREVIEW_LIMIT = 20;

/** Cap map pins returned with each home-feed card. */
export const FEED_MAP_PIN_LIMIT = 8;

export type FeedThreadPreviewItem = {
  id: string;
  contentText: string | null;
  mediaUrl: string | null;
  placeName: string | null;
  likeCount: number;
  createdAt: string;
};

export type FeedMapPin = {
  lat: number;
  lng: number;
  name?: string | null;
};

function parseGps(raw: unknown): { lat: number; lng: number } | null {
  if (!raw || typeof raw !== "object") return null;
  const gps = raw as { lat?: unknown; lng?: unknown };
  const lat = typeof gps.lat === "number" ? gps.lat : Number(gps.lat);
  const lng = typeof gps.lng === "number" ? gps.lng : Number(gps.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) return null;
  return { lat, lng };
}

function pinKey(lat: number, lng: number): string {
  return `${lat.toFixed(5)},${lng.toFixed(5)}`;
}

/**
 * Batch-load swipeable thread snippets for home-feed cards.
 * One windowed SQL pass ranks entries per trip (likeCount, then createdAt),
 * then a single Prisma hydrate loads media/place for those ids only.
 * Caps each trip at FEED_THREAD_PREVIEW_LIMIT so long threads stay bounded.
 */
export async function loadFeedThreadPreviews(
  tripIds: string[]
): Promise<Map<string, FeedThreadPreviewItem[]>> {
  const result = new Map<string, FeedThreadPreviewItem[]>();
  if (tripIds.length === 0) return result;
  for (const id of tripIds) result.set(id, []);

  const ranked = await prisma.$queryRaw<Array<{ id: string }>>(Prisma.sql`
    SELECT id
    FROM (
      SELECT
        e.id,
        ROW_NUMBER() OVER (
          PARTITION BY e."tripId"
          ORDER BY e."likeCount" DESC, e."createdAt" DESC
        ) AS rn
      FROM "trip_thread_entries" e
      WHERE e."tripId" IN (${Prisma.join(tripIds)})
    ) ranked
    WHERE rn <= ${FEED_THREAD_PREVIEW_LIMIT}
  `);

  if (ranked.length === 0) return result;

  const rows = await prisma.tripThreadEntry.findMany({
    where: { id: { in: ranked.map((row) => row.id) } },
    orderBy: [{ likeCount: "desc" }, { createdAt: "desc" }],
    select: {
      id: true,
      tripId: true,
      contentText: true,
      locationName: true,
      likeCount: true,
      createdAt: true,
      media: { select: { url: true } },
      place: { select: { name: true } },
    },
  });

  for (const row of rows) {
    const list = result.get(row.tripId);
    if (!list || list.length >= FEED_THREAD_PREVIEW_LIMIT) continue;
    list.push({
      id: row.id,
      contentText: row.contentText ?? null,
      mediaUrl: row.media?.url ?? null,
      placeName: row.place?.name ?? row.locationName ?? null,
      likeCount: row.likeCount,
      createdAt: row.createdAt.toISOString(),
    });
  }

  return result;
}

/**
 * Batch-load map pins for home-feed cards from PlaceOnTrip, LOCATION entries,
 * and trip start/end places. Caps per trip.
 */
export async function loadFeedMapPins(
  tripIds: string[]
): Promise<Map<string, FeedMapPin[]>> {
  const result = new Map<string, FeedMapPin[]>();
  if (tripIds.length === 0) return result;
  for (const id of tripIds) result.set(id, []);

  const [visits, locationEntries, trips] = await Promise.all([
    prisma.placeOnTrip.findMany({
      where: { tripId: { in: tripIds } },
      orderBy: [{ order: "asc" }, { visitedAt: "asc" }],
      select: {
        tripId: true,
        place: { select: { lat: true, lng: true, name: true } },
      },
    }),
    prisma.tripThreadEntry.findMany({
      where: {
        tripId: { in: tripIds },
        OR: [{ placeId: { not: null } }, { type: ThreadEntryType.LOCATION }],
      },
      orderBy: [{ createdAt: "asc" }],
      select: {
        tripId: true,
        locationName: true,
        gpsCoordinates: true,
        place: { select: { lat: true, lng: true, name: true } },
      },
    }),
    prisma.trip.findMany({
      where: { id: { in: tripIds } },
      select: {
        id: true,
        startLocation: { select: { lat: true, lng: true, name: true } },
        endLocation: { select: { lat: true, lng: true, name: true } },
      },
    }),
  ]);

  const seenByTrip = new Map<string, Set<string>>();
  const seenFor = (tripId: string) => {
    let set = seenByTrip.get(tripId);
    if (!set) {
      set = new Set();
      seenByTrip.set(tripId, set);
    }
    return set;
  };

  const pushPin = (
    tripId: string,
    lat: number,
    lng: number,
    name?: string | null
  ) => {
    const list = result.get(tripId);
    if (!list || list.length >= FEED_MAP_PIN_LIMIT) return;
    const key = pinKey(lat, lng);
    const tripSeen = seenFor(tripId);
    if (tripSeen.has(key)) return;
    tripSeen.add(key);
    list.push({ lat, lng, name: name ?? null });
  };

  for (const visit of visits) {
    pushPin(visit.tripId, visit.place.lat, visit.place.lng, visit.place.name);
  }

  for (const entry of locationEntries) {
    if (entry.place) {
      pushPin(
        entry.tripId,
        entry.place.lat,
        entry.place.lng,
        entry.place.name ?? entry.locationName
      );
      continue;
    }
    const gps = parseGps(entry.gpsCoordinates);
    if (gps) {
      pushPin(entry.tripId, gps.lat, gps.lng, entry.locationName);
    }
  }

  for (const trip of trips) {
    if (trip.startLocation) {
      pushPin(
        trip.id,
        trip.startLocation.lat,
        trip.startLocation.lng,
        trip.startLocation.name
      );
    }
    if (trip.endLocation) {
      pushPin(
        trip.id,
        trip.endLocation.lat,
        trip.endLocation.lng,
        trip.endLocation.name
      );
    }
  }

  return result;
}
