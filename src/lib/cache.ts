import { ENV } from "@/env";

type JsonValue = any;

// Simple Upstash REST client (lazy) to avoid bringing redis client
async function upstashFetch<T = unknown>(
  path: string,
  body: unknown
): Promise<T | null> {
  if (!ENV.REDIS_REST_URL || !ENV.REDIS_REST_TOKEN) return null as any;
  const res = await fetch(`${ENV.REDIS_REST_URL}/${path}`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${ENV.REDIS_REST_TOKEN}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
    // Next fetch caching should be bypassed
    cache: "no-store",
  } as any);
  if (!res.ok) return null as any;
  const json = await res.json();
  // Upstash REST returns { result: ... }
  return (json?.result ?? null) as T | null;
}

export async function cacheGetJson<T = JsonValue>(
  key: string
): Promise<T | null> {
  const result = await upstashFetch<string>("get", [key]);
  if (!result) return null;
  try {
    return JSON.parse(result) as T;
  } catch {
    return null;
  }
}

export async function cacheSetJson(
  key: string,
  value: JsonValue,
  ttlSeconds?: number
): Promise<boolean> {
  const payload = ttlSeconds
    ? ["setex", key, ttlSeconds, JSON.stringify(value)]
    : ["set", key, JSON.stringify(value)];
  const result = await upstashFetch<"OK">("pipeline", [payload]);
  return result === "OK";
}

export function bucketCoord(value: number, decimals = 5): number {
  const factor = Math.pow(10, decimals);
  return Math.round(value * factor) / factor;
}

export const cacheKeys = {
  search: (
    q: string,
    lat?: number,
    lng?: number,
    type?: string,
    limit?: number
  ) =>
    `plc:srch:${q}:${lat != null ? bucketCoord(lat) : ""}:${
      lng != null ? bucketCoord(lng) : ""
    }:${type ?? ""}:${limit ?? ""}`,
  nearby: (lat: number, lng: number, kinds?: string) =>
    `plc:nby:${bucketCoord(lat)}:${bucketCoord(lng)}:${kinds ?? ""}`,
};
