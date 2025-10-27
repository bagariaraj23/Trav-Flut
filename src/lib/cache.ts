import { ENV } from '@/env';

type JsonValue =
  | string
  | number
  | boolean
  | null
  | JsonValue[]
  | { [key: string]: JsonValue };

// Constants for cache configuration
const DEFAULT_MAX_SIZE = 1000;
const MAX_MEMORY_ITEMS = 1000;
const DEFAULT_MEMORY_TTL = 5 * 60 * 1000; // 5 minutes


export interface CacheStats {
  hits: number;
  misses: number;
  size: number;
  maxSize: number;
}

interface CacheValue<V> {
  data: V;
  lastAccessed: number;
  expiry: number | null;
}

export class LRUCache<K, V> {
  private cache: Map<K, CacheValue<V>>;
  private readonly maxSize: number;
  private hits: number;
  private misses: number;

  constructor(maxSize: number = DEFAULT_MAX_SIZE) {
    if (maxSize <= 0) {
      throw new Error('Cache max size must be positive');
    }
    this.cache = new Map();
    this.maxSize = maxSize;
    this.hits = 0;
    this.misses = 0;
  }

  private isExpired(value: CacheValue<V>): boolean {
    return value.expiry !== null && Date.now() > value.expiry;
  }

  private evictExpired(): void {
    const now = Date.now();
    this.cache.forEach((value, key) => {
      if (value.expiry !== null && now > value.expiry) {
        this.cache.delete(key);
      }
    });
  }

  private evictLRU(): void {
    if (this.cache.size === 0) return;

    let oldestKey: K | null = null;
    let oldestAccess = Infinity;

    this.cache.forEach((value, key) => {
      if (value.lastAccessed < oldestAccess) {
        oldestAccess = value.lastAccessed;
        oldestKey = key;
      }
    });

    if (oldestKey !== null) {
      this.cache.delete(oldestKey);
    }
  }

  get(key: K): V | undefined {
    const value = this.cache.get(key);

    if (!value) {
      this.misses++;
      return undefined;
    }

    if (this.isExpired(value)) {
      this.cache.delete(key);
      this.misses++;
      return undefined;
    }

    this.hits++;
    value.lastAccessed = Date.now();
    return value.data;
  }

  set(key: K, value: V, ttlMs?: number): void {
    if (key === undefined || key === null) {
      throw new Error('Cache key cannot be undefined or null');
    }

    if (value === undefined) {
      throw new Error('Cache value cannot be undefined');
    }

    this.evictExpired();

    if (this.cache.size >= this.maxSize) {
      this.evictLRU();
    }

    const cacheValue: CacheValue<V> = {
      data: value,
      lastAccessed: Date.now(),
      expiry: ttlMs ? Date.now() + ttlMs : null
    };

    this.cache.set(key, cacheValue);
  }

  delete(key: K): boolean {
    return this.cache.delete(key);
  }

  clear(): void {
    this.cache.clear();
    this.hits = 0;
    this.misses = 0;
  }

  getStats(): CacheStats {
    this.evictExpired();
    return {
      hits: this.hits,
      misses: this.misses,
      size: this.cache.size,
      maxSize: this.maxSize
    };
  }

  size(): number {
    this.evictExpired();
    return this.cache.size;
  }

  has(key: K): boolean {
    const value = this.cache.get(key);
    if (!value) return false;
    if (this.isExpired(value)) {
      this.cache.delete(key);
      return false;
    }
    return true;
  }

  keys(): IterableIterator<K> {
    this.evictExpired();
    return this.cache.keys();
  }

  values(): IterableIterator<V> {
    this.evictExpired();
    const values = Array.from(this.cache.values())
      .map(value => value.data);
    return values[Symbol.iterator]();
  }

  entries(): IterableIterator<[K, V]> {
    this.evictExpired();
    const entries = Array.from(this.cache.entries())
      .map(([key, value]) => [key, value.data] as [K, V]);
    return entries[Symbol.iterator]();
  }
}



// Global memory cache instance
const memoryCache = new LRUCache<string, { value: string; expiresAt: number }>(DEFAULT_MAX_SIZE);

// Simple Upstash REST client (lazy) to avoid bringing redis client
async function upstashFetch<T = unknown>(
  path: string,
  body: unknown
): Promise<T | null> {
  if (!ENV.REDIS_REST_URL || !ENV.REDIS_REST_TOKEN) return null;

  try {
    const res = await fetch(`${ENV.REDIS_REST_URL}/${path}`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${ENV.REDIS_REST_TOKEN}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(body),
      cache: "no-store",
    });

    if (!res.ok) {
      console.warn(`[Cache] Upstash request failed: ${res.status} ${res.statusText}`);
      return null;
    }

    const json = await res.json();
    // Upstash REST returns { result: ... }
    return (json?.result ?? null) as T | null;
  } catch (error) {
    console.error('[Cache] Upstash request error:', error);
    return null;
  }
}

export async function cacheGetJson<T = JsonValue>(
  key: string
): Promise<T | null> {
  // Check memory cache first
  const memEntry = memoryCache.get(key);
  if (memEntry) {
    if (Date.now() < memEntry.expiresAt) {
      try {
        return JSON.parse(memEntry.value) as T;
      } catch {
        memoryCache.delete(key);
      }
    } else {
      memoryCache.delete(key);
    }
  }

  // Try Redis cache
  const result = await upstashFetch<string>("get", [key]);
  if (!result) return null;

  try {
    const parsed = JSON.parse(result) as T;

    // Update memory cache
    memoryCache.set(key, {
      value: result,
      expiresAt: Date.now() + DEFAULT_MEMORY_TTL
    });

    return parsed;
  } catch {
    return null;
  }
}

export async function cacheSetJson(
  key: string,
  value: JsonValue,
  ttlSeconds?: number
): Promise<boolean> {
  const stringValue = JSON.stringify(value);

  // Set in Redis
  const payload = ttlSeconds
    ? ["setex", key, ttlSeconds, stringValue]
    : ["set", key, stringValue];
  const result = await upstashFetch<"OK">("pipeline", [payload]);

  // Set in memory cache
  if (result === "OK") {
    memoryCache.set(key, {
      value: stringValue,
      expiresAt: Date.now() + (ttlSeconds ? ttlSeconds * 1000 : DEFAULT_MEMORY_TTL)
    });
  }

  return result === "OK";
}

/**
 * Rounds a coordinate to a specific number of decimal places for cache key generation
 */
export function bucketCoord(value: number, decimals = 5): number {
  const factor = Math.pow(10, decimals);
  return Math.round(value * factor) / factor;
}

/**
 * Cache key generators for different types of place queries
 */
export const cacheKeys = {
  /**
   * Generate a cache key for place search queries
   */
  search: (
    q: string,
    lat?: number,
    lng?: number,
    type?: string,
    limit?: number
  ): string => {
    const parts = [
      'plc:srch',
      q,
      lat != null ? bucketCoord(lat).toString() : '',
      lng != null ? bucketCoord(lng).toString() : '',
      type ?? '',
      limit?.toString() ?? ''
    ];
    return parts.join(':');
  },

  /**
   * Generate a cache key for nearby place queries
   */
  nearby: (lat: number, lng: number, kinds?: string): string => {
    const parts = [
      'plc:nby',
      bucketCoord(lat).toString(),
      bucketCoord(lng).toString(),
      kinds ?? ''
    ];
    return parts.join(':');
  }
};
