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

// Track if Upstash is rate-limited to avoid unnecessary requests
let upstashRateLimited = false;
let upstashRateLimitResetTime = 0;

// Cache performance metrics
interface CacheMetrics {
  redisHits: number;
  redisMisses: number;
  memoryHits: number;
  memoryMisses: number;
  totalGets: number;
  totalSets: number;
  batchOperations: number;
  errors: number;
  lastReset: number;
}

let cacheMetrics: CacheMetrics = {
  redisHits: 0,
  redisMisses: 0,
  memoryHits: 0,
  memoryMisses: 0,
  totalGets: 0,
  totalSets: 0,
  batchOperations: 0,
  errors: 0,
  lastReset: Date.now(),
};

export function getCacheMetrics(): CacheMetrics & {
  redisHitRate: number;
  memoryHitRate: number;
  overallHitRate: number;
} {
  const totalRedisOps = cacheMetrics.redisHits + cacheMetrics.redisMisses;
  const totalMemoryOps = cacheMetrics.memoryHits + cacheMetrics.memoryMisses;
  const totalOps = cacheMetrics.totalGets;

  const uniqueHits = cacheMetrics.memoryHits + cacheMetrics.redisHits;
  const overallHitRate = totalOps > 0 ? Math.min(uniqueHits / totalOps, 1.0) : 0;

  return {
    ...cacheMetrics,
    redisHitRate: totalRedisOps > 0 ? cacheMetrics.redisHits / totalRedisOps : 0,
    memoryHitRate: totalMemoryOps > 0 ? cacheMetrics.memoryHits / totalMemoryOps : 0,
    overallHitRate,
  };
}

export function resetCacheMetrics(): void {
  cacheMetrics = {
    redisHits: 0,
    redisMisses: 0,
    memoryHits: 0,
    memoryMisses: 0,
    totalGets: 0,
    totalSets: 0,
    batchOperations: 0,
    errors: 0,
    lastReset: Date.now(),
  };
}

export function resetUpstashRateLimit(): void {
  upstashRateLimited = false;
  upstashRateLimitResetTime = 0;
}

// Export function to check rate limit status
export function getUpstashRateLimitStatus(): { isLimited: boolean; resetTime?: number; remainingMs?: number } {
  if (!upstashRateLimited) {
    return { isLimited: false };
  }
  const remainingMs = upstashRateLimitResetTime - Date.now();
  return {
    isLimited: remainingMs > 0,
    resetTime: upstashRateLimitResetTime,
    remainingMs: remainingMs > 0 ? remainingMs : 0,
  };
}

// Simple Upstash REST client (lazy) to avoid bringing redis client
async function upstashFetch<T = unknown>(
  path: string,
  body: unknown
): Promise<T | null> {
  if (!ENV.REDIS_REST_URL || !ENV.REDIS_REST_TOKEN) {
    console.warn('[Cache] Redis credentials not configured');
    return null;
  }

  // Check if we're rate-limited and should skip requests
  if (upstashRateLimited && Date.now() < upstashRateLimitResetTime) {
    const remainingMs = upstashRateLimitResetTime - Date.now();
    const remainingMins = Math.round(remainingMs / 60000);
    console.warn(`[Cache] Upstash rate limit active, skipping request. Resets in ${remainingMins} minutes.`);
    return null;
  }

  // If rate limit time has passed, reset the flag
  if (upstashRateLimited && Date.now() >= upstashRateLimitResetTime) {
    upstashRateLimited = false;
    upstashRateLimitResetTime = 0;
  }

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
      const text = await res.text();
      console.warn(`[Cache] Upstash request failed: ${res.status} ${res.statusText}`, {
        status: res.status,
        statusText: res.statusText,
        responsePreview: text.substring(0, 200),
      });

      // Check for rate limit errors
      if (res.status === 400 || res.status === 429) {
        if (text.includes('max requests limit exceeded') || text.includes('rate limit')) {
          upstashRateLimited = true;
          // Reset after 1 hour (conservative estimate)
          upstashRateLimitResetTime = Date.now() + 60 * 60 * 1000;
          console.warn(`[Cache] Upstash rate limit detected. Disabling Upstash for 1 hour.`);
        } else {
          // 400/429 but not rate limit - log the actual error
          console.error(`[Cache] Upstash returned ${res.status} but not rate limit. Response: ${text.substring(0, 500)}`);
        }
      }
      return null;
    }

    // Success - reset rate limit flag if it was set
    if (upstashRateLimited) {
      upstashRateLimited = false;
      upstashRateLimitResetTime = 0;
    }

    const json = await res.json();
    
    if (path === 'pipeline') {
      let rawResult: unknown = json;
      
      if (Array.isArray(json)) {
        rawResult = json;
      } else if (json?.result && Array.isArray(json.result)) {
        rawResult = json.result;
      } else if (json && typeof json === 'object' && !Array.isArray(json)) {
        const keys = Object.keys(json).sort((a, b) => parseInt(a) - parseInt(b));
        if (keys.length > 0 && keys.every(k => !isNaN(parseInt(k)))) {
          rawResult = keys.map(k => json[k]);
        }
      }
      
      if (Array.isArray(rawResult)) {
        return rawResult.map((item: unknown) => {
          if (typeof item === 'object' && item !== null && 'result' in item) {
            return (item as { result: unknown }).result;
          }
          return item;
        }) as T;
      }
      
      return rawResult as T;
    }
    
    return (json?.result ?? null) as T | null;
  } catch (error) {
    // Check if error message indicates rate limit
    if (error instanceof Error && error.message.includes('max requests limit exceeded')) {
      upstashRateLimited = true;
      upstashRateLimitResetTime = Date.now() + 60 * 60 * 1000;
      console.warn(`[Cache] Upstash rate limit detected from error. Disabling Upstash for 1 hour.`);
    } else {
      // Log the actual error for debugging
      console.error('[Cache] Upstash request error:', {
        error: error instanceof Error ? error.message : String(error),
        stack: error instanceof Error ? error.stack : undefined,
        url: `${ENV.REDIS_REST_URL}/${path}`,
      });
    }
    return null;
  }
}

export async function cacheGetJson<T = JsonValue>(
  key: string
): Promise<T | null> {
  cacheMetrics.totalGets++;
  
  // Check memory cache first
  const memEntry = memoryCache.get(key);
  if (memEntry) {
    if (Date.now() < memEntry.expiresAt) {
      try {
        cacheMetrics.memoryHits++;
        return JSON.parse(memEntry.value) as T;
      } catch {
        memoryCache.delete(key);
        cacheMetrics.memoryMisses++;
      }
    } else {
      memoryCache.delete(key);
      cacheMetrics.memoryMisses++;
    }
  } else {
    cacheMetrics.memoryMisses++;
  }

  // Try Redis cache
  const result = await upstashFetch<string>("get", [key]);
  if (!result) {
    cacheMetrics.redisMisses++;
    return null;
  }

  try {
    const parsed = JSON.parse(result) as T;
    cacheMetrics.redisHits++;

    // Update memory cache
    memoryCache.set(key, {
      value: result,
      expiresAt: Date.now() + DEFAULT_MEMORY_TTL
    });

    return parsed;
  } catch {
    cacheMetrics.redisMisses++;
    cacheMetrics.errors++;
    return null;
  }
}

/**
 * Batch get multiple cache keys in a single Upstash request
 * Returns a map of key -> value (or null if not found)
 */
export async function cacheGetJsonBatch<T = JsonValue>(
  keys: string[]
): Promise<Map<string, T | null>> {
  const results = new Map<string, T | null>();
  
  cacheMetrics.totalGets += keys.length;
  
  // Check memory cache first for all keys
  const keysToFetch: string[] = [];
  for (const key of keys) {
    const memEntry = memoryCache.get(key);
    if (memEntry && Date.now() < memEntry.expiresAt) {
      try {
        results.set(key, JSON.parse(memEntry.value) as T);
        cacheMetrics.memoryHits++;
      } catch {
        memoryCache.delete(key);
        keysToFetch.push(key);
        cacheMetrics.memoryMisses++;
      }
    } else {
      if (memEntry) memoryCache.delete(key);
      keysToFetch.push(key);
      cacheMetrics.memoryMisses++;
    }
  }

  // If all keys were in memory cache, return early
  if (keysToFetch.length === 0) {
    return results;
  }

  // Batch fetch remaining keys from Redis using MGET
  if (keysToFetch.length > 0) {
    cacheMetrics.batchOperations++;
    const pipeline = keysToFetch.map(key => ["get", key] as [string, string]);
    const redisResults = await upstashFetch<(string | null)[]>("pipeline", pipeline);
    
    if (redisResults && Array.isArray(redisResults)) {
      let hits = 0;
      let misses = 0;
      
      for (let i = 0; i < keysToFetch.length; i++) {
        const key = keysToFetch[i];
        const value: unknown = redisResults[i];
        
        let stringValue: string | null = null;
        
        if (value === null || value === undefined) {
          stringValue = null;
        } else if (typeof value === 'string') {
          stringValue = value;
        } else if (typeof value === 'object' && value !== null && 'result' in value) {
          const result = (value as { result: unknown }).result;
          if (typeof result === 'string') {
            stringValue = result;
          } else if (result === null) {
            stringValue = null;
          } else {
            stringValue = JSON.stringify(result);
          }
        }
        
        if (stringValue && stringValue.length > 0) {
          try {
            const parsed = JSON.parse(stringValue) as T;
            results.set(key, parsed);
            hits++;
            cacheMetrics.redisHits++;
            memoryCache.set(key, {
              value: stringValue,
              expiresAt: Date.now() + DEFAULT_MEMORY_TTL
            });
          } catch {
            results.set(key, stringValue as T);
            hits++;
            cacheMetrics.redisHits++;
            memoryCache.set(key, {
              value: stringValue,
              expiresAt: Date.now() + DEFAULT_MEMORY_TTL
            });
          }
        } else {
          results.set(key, null);
          misses++;
          cacheMetrics.redisMisses++;
        }
      }
      
    } else {
      // If batch fetch failed, mark all as null
      // Check if it's due to rate limiting or other issues
      if (!ENV.REDIS_REST_URL || !ENV.REDIS_REST_TOKEN) {
        console.warn(`[Cache] Batch fetch skipped: Redis credentials not configured`);
      } else if (upstashRateLimited) {
        const remainingMs = upstashRateLimitResetTime - Date.now();
        const remainingMins = Math.round(remainingMs / 60000);
        console.warn(`[Cache] Batch fetch skipped: Rate limit active (resets in ${remainingMins} minutes)`);
      }
      for (const key of keysToFetch) {
        results.set(key, null);
      }
    }
  }

  return results;
}

export async function cacheSetJson<T = any>(
  key: string,
  value: T,
  ttlSeconds?: number
): Promise<boolean> {
  cacheMetrics.totalSets++;
  
  // Validate JSON serializable
  let stringValue: string;
  try {
    stringValue = JSON.stringify(value);
  } catch (error) {
    console.error("[Cache] Value is not JSON serializable to string:", error);
    cacheMetrics.errors++;
    return false;
  }

  // Set in Redis
  const payload = ttlSeconds
    ? ["setex", key, ttlSeconds, stringValue]
    : ["set", key, stringValue];
  const result = await upstashFetch<string | string[]>("pipeline", [payload]);

  // Pipeline returns array, extract first result
  const success = Array.isArray(result) 
    ? result[0] === "OK" || (typeof result[0] === 'string' && result[0].toUpperCase() === 'OK')
    : result === "OK";

  // Set in memory cache
  if (success) {
    memoryCache.set(key, {
      value: stringValue,
      expiresAt:
        Date.now() + (ttlSeconds ? ttlSeconds * 1000 : DEFAULT_MEMORY_TTL),
    });
  } else {
    cacheMetrics.errors++;
  }

  return success;
}

/**
 * Base62 encoding for more compact keys while remaining URL-safe
 * Using a modified base62 that's case-sensitive for more density
 */
const base62Chars = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";

function toBase62(num: number): string {
  if (num === 0) return "0";
  let result = "";
  while (num > 0) {
    result = base62Chars[num % 62] + result;
    num = Math.floor(num / 62);
  }
  return result;
}

/**
 * Rounds and encodes a coordinate for cache key generation
 * Uses 4 decimals (11.1m precision) instead of 5 (1.1m precision)
 * Encodes as base62 for shorter strings
 */
export function bucketCoord(value: number): string {
  // Use 4 decimals (11.1m precision) instead of 5
  const factor = 10000;
  const encoded = toBase62(Math.round(value * factor));
  return encoded;
}

/**
 * Cache key generators for different types of place queries
 * Optimized for storage reduction:
 * - Shorter prefixes (p=place, s=search, n=nearby)
 * - Base62 encoded coordinates
 * - Minimal separators
 * - Optional params omitted entirely instead of empty strings
 */
export const cacheKeys = {
  /**
   * Primary place storage key
   * Format: p:{id} - Stores full place data
   */
  place: (id: string): string => `p:${id}`,

  /**
   * Place reference by external ID
   * Format: p:e:{externalId} - Stores only place ID reference
   */
  placeByExternal: (externalId: string): string => `p:e:${externalId}`,

  /**
   * Place reference by spatial key
   * Format: p:s:{spatialKey} - Stores only place ID reference
   */
  placeBySpatial: (spatialKey: string): string => `p:s:${spatialKey}`,

  /**
   * Place reference by name and spatial key
   * Format: p:n:{nameLower}:{spatialKey} - Stores only place ID reference
   */
  placeByName: (name: string, spatialKey: string): string =>
    `p:n:${name.toLowerCase()}:${spatialKey}`,

  /**
   * Generate a compact cache key for place search queries
   * Format: p:q:{query}{lat}{lng}{type}{limit}
   */
  search: (
    q: string,
    lat?: number,
    lng?: number,
    type?: string,
    limit?: number
  ): string => {
    // Start with minimal prefix
    let key = 'p:q:' + q;

    // Only add coordinates if both are present
    if (lat != null && lng != null) {
      key += ',' + bucketCoord(lat) + bucketCoord(lng);
    }

    // Only add type and limit if specified
    if (type) key += ',' + type;
    if (limit) key += ',' + limit;

    return key;
  },

  /**
   * Generate a compact cache key for nearby place queries
   * Format: p:n:{lat}{lng}{kinds}
   */
  nearby: (lat: number, lng: number, kinds?: string): string => {
    let key = 'p:n:' + bucketCoord(lat) + bucketCoord(lng);
    if (kinds) key += ',' + kinds;
    return key;
  }
};

export async function cacheDelete(key: string): Promise<boolean> {
  // Always clear memory cache
  memoryCache.delete(key);

  if (!ENV.REDIS_REST_URL || !ENV.REDIS_REST_TOKEN) {
    return true; // Consider memory-only deletion successful
  }

  try {
    const result = await upstashFetch<number>("pipeline", [["del", key]]);
    return result === 1; // DEL returns number of keys removed
  } catch (error) {
    console.error("[Cache] Delete failed:", error);
    return false;
  }
}

/**
 * Get a place by reference lookup (two-step)
 * First fetches the reference, then the full place data
 */
export async function getPlaceByRef<T>(
  refKey: string,
  options: {
    transform?: (place: T) => T;
  } = {}
): Promise<T | null> {
  // Get the reference
  const ref = await cacheGetJson<{ id: string }>(refKey);
  if (!ref?.id) return null;

  // Get the full place data
  const place = await cacheGetJson<T>(cacheKeys.place(ref.id));
  if (!place) return null;

  // Apply optional transform
  return options.transform ? options.transform(place) : place;
}

/**
 * Delete a place and all its references from cache
 */
export async function deletePlaceFromCache(
  place: {
    id: string;
    externalId?: string;
    name: string;
  },
  spatialKey: string
): Promise<void> {
  const keys = [
    cacheKeys.place(place.id),
    cacheKeys.placeBySpatial(spatialKey),
    cacheKeys.placeByName(place.name, spatialKey)
  ];

  if (place.externalId) {
    keys.push(cacheKeys.placeByExternal(place.externalId));
  }

  // Delete all keys in parallel
  await Promise.all(keys.map(key => cacheDelete(key)));
}

export { upstashFetch }