import { Redis } from '@upstash/redis';
import { ENV } from '@/env';
import { LRUCache } from './cache';
import { isRedisCircuitOpen, withRedisDeadline } from './redisGuard';

// Constants
const HOUR_IN_MS = 3600000; // 1 hour in milliseconds
const DEFAULT_MAX_SIZE = 1000;
const DEFAULT_CACHE_TTL = HOUR_IN_MS;

interface RedisValue<T> {
    data: T;
    timestamp: number;
}

// Initialize Redis client if configured
export const redis = ENV.REDIS_REST_URL && ENV.REDIS_REST_TOKEN
    ? new Redis({
        url: ENV.REDIS_REST_URL,
        token: ENV.REDIS_REST_TOKEN,
    })
    : null;

// Initialize memory cache
export const memoryCache = new LRUCache<string, unknown>(DEFAULT_MAX_SIZE);

const inflightGets = new Map<string, Promise<unknown>>();

function delay(ms: number): Promise<void> {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function readRedisValue<T>(key: string, ttl: number): Promise<T | undefined> {
    if (!redis || isRedisCircuitOpen()) return undefined;
    try {
        const cachedValue = await withRedisDeadline(() => redis!.get<RedisValue<T>>(key));
        if (cachedValue && cachedValue.timestamp + ttl > Date.now()) {
            return cachedValue.data;
        }
    } catch {
        return undefined;
    }
    return undefined;
}

async function writeRedisValue<T>(key: string, value: T, ttl: number): Promise<void> {
    if (!redis || isRedisCircuitOpen() || value === undefined || value === null) return;
    const redisValue: RedisValue<T> = {
        data: value,
        timestamp: Date.now(),
    };
    try {
        await withRedisDeadline(() =>
            redis!.set(key, redisValue, { ex: Math.max(1, Math.floor(ttl / 1000)) })
        );
    } catch {
        // Memory cache still holds the value for this instance.
    }
}

/**
 * Drop a cached key from memory and Redis. Used when a short-lived badge
 * must refresh before its TTL (notification unread count).
 */
export async function invalidateCachedKey(key: string): Promise<void> {
    memoryCache.delete(key);
    if (!redis || isRedisCircuitOpen()) return;
    try {
        await withRedisDeadline(() => redis!.del(key));
    } catch {
        // The key expires on its own TTL.
    }
}

/**
 * Multi-level cache. A single in-process flight plus a short Redis SET NX
 * lock keeps concurrent misses from stampeding the getter.
 */
export async function getOrSet<T>(
    key: string,
    getter: () => Promise<T>,
    ttl: number = DEFAULT_CACHE_TTL
): Promise<T> {
    const memValue = memoryCache.get(key) as T | undefined;
    if (memValue !== undefined) {
        return memValue;
    }

    const cached = await readRedisValue<T>(key, ttl);
    if (cached !== undefined) {
        memoryCache.set(key, cached, ttl);
        return cached;
    }

    const existing = inflightGets.get(key) as Promise<T> | undefined;
    if (existing) {
        return existing;
    }

    const flight = (async () => {
        const lockKey = `cache-lock:${key}`;
        let locked = false;
        if (redis && !isRedisCircuitOpen()) {
            try {
                const acquired = await withRedisDeadline(() =>
                    redis!.set(lockKey, "1", { nx: true, px: 8000 })
                );
                locked = acquired === "OK";
            } catch {
                locked = false;
            }
        }

        if (!locked && redis) {
            for (let attempt = 0; attempt < 5; attempt++) {
                await delay(80 * (attempt + 1));
                const retried = await readRedisValue<T>(key, ttl);
                if (retried !== undefined) {
                    memoryCache.set(key, retried, ttl);
                    return retried;
                }
            }
        }

        const value = await getter();
        if (value !== undefined && value !== null) {
            memoryCache.set(key, value, ttl);
            await writeRedisValue(key, value, ttl);
        }

        if (locked && redis) {
            try {
                await redis.del(lockKey);
            } catch {
                // Lock TTL releases it.
            }
        }
        return value;
    })();

    inflightGets.set(key, flight);
    try {
        return await flight;
    } finally {
        inflightGets.delete(key);
    }
}

/**
 * Clear all caches (memory and Redis if configured)
 */
export async function clearCaches(): Promise<void> {
    memoryCache.clear();
    if (redis) {
        await redis.flushall();
    }
}

/**
 * Get cache statistics
 */
export function getCacheStats() {
    const stats = memoryCache.getStats();
    return {
        memory: stats,
        redis: redis ? 'connected' : 'disabled'
    };
}