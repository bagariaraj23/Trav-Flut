import { Redis } from '@upstash/redis';
import { ENV } from '@/env';
import { LRUCache } from './cache';

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

/**
 * Multi-level caching utility that combines in-memory LRU cache with Redis
 * for distributed caching across serverless functions.
 */
export async function getOrSet<T>(
    key: string,
    getter: () => Promise<T>,
    ttl: number = DEFAULT_CACHE_TTL
): Promise<T> {
    // Try memory cache first
    const memValue = memoryCache.get(key) as T | undefined;
    if (memValue !== undefined) {
        return memValue;
    }

    if (redis) {
        // Try Redis cache next
        const cachedValue = await redis.get<RedisValue<T>>(key);

        if (cachedValue && cachedValue.timestamp + ttl > Date.now()) {
            // Cache hit - update memory cache and return
            memoryCache.set(key, cachedValue.data, ttl);
            return cachedValue.data;
        }
    }

    // Cache miss - fetch fresh value
    const value = await getter();

    // Update both caches
    if (value !== undefined && value !== null) {
        const redisValue: RedisValue<T> = {
            data: value,
            timestamp: Date.now()
        };

        if (redis) {
            await redis.set(key, redisValue, { ex: Math.floor(ttl / 1000) });
        }
        memoryCache.set(key, value, ttl);
    }

    return value;
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