import { prisma } from "@/lib/prisma";
import { cacheGetJson, cacheSetJson, cacheKeys } from "@/lib/cache";
import { rlKeyFromUserOrIp, rateLimit } from "@/lib/rateLimit";
import { MapboxPlacesAdapter } from "@/lib/mapProviders/mapbox";
import type { NormalizedPlace } from "@/lib/mapProviders/adapter";

const placesProvider = new MapboxPlacesAdapter();

export async function searchPlaces(params: {
  q: string;
  lat?: number;
  lng?: number;
  limit?: number;
  userId?: string;
  ip?: string;
}) {
  const { q, lat, lng, limit = 10, userId, ip } = params;
  const rl = await rateLimit(
    rlKeyFromUserOrIp(userId, ip, "places:search"),
    30,
    60
  );
  if (!rl.allowed) return [] as NormalizedPlace[];

  const key = cacheKeys.search(q, lat, lng, undefined, limit);
  const cached = await cacheGetJson<NormalizedPlace[]>(key);
  if (cached) return cached;

  const results = await placesProvider.search({ q, lat, lng, limit });
  await cacheSetJson(key, results, 600);
  return results;
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
  // 1) externalId lookup
  if (input.externalId) {
    const existingByExt = await prisma.place.findUnique({
      where: { externalId: input.externalId },
    });
    if (existingByExt)
      return { placeId: existingByExt.id, place: existingByExt };
  }

  // 2) name + 25m radius dedupe
  const lat = input.lat;
  const lng = input.lng;
  const name = input.name.trim();
  const nearby = await prisma.place.findMany({
    where: {
      name: { equals: name, mode: "insensitive" },
      lat: { gte: lat - 0.00025, lte: lat + 0.00025 },
      lng: { gte: lng - 0.00025, lte: lng + 0.00025 },
    },
    take: 5,
  });
  if (nearby.length > 0) {
    const p = nearby[0];
    return { placeId: p.id, place: p };
  }

  // 3) upsert new
  const place = await prisma.place.create({
    data: {
      name,
      address: input.address,
      lat,
      lng,
      placeType: (input.placeType as any) ?? "POI",
      source: (input.source as any) ?? "USER",
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
