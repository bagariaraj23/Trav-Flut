import { redis } from './redis';
import { ENV } from '@/env';
import { upstashFetch } from './cache';

const DEFAULT_LOCK_TTL = 5000; // 5 seconds

async function upstashAcquireLock(key: string, ttl: number) {
    if (!ENV.REDIS_REST_TOKEN || !ENV.REDIS_REST_URL) {
        console.warn("[Mutex] No Redis configuration - locks disabled");
        return false;
    }

    // Use SET key value NX PX ttl
    try {
        const command = ["set", `mutex:${key}`, Date.now().toString(), "px", ttl.toString(), "nx"];
        const res = await upstashFetch<string>("pipeline", [command]);
        return res === "OK";
    } catch (e) {
        console.error("[Mutex] Lock acquisition failed:", e);
        throw new Error("Failed to acquire lock");
    }
}

export async function acquireLock(key: string, ttl: number = DEFAULT_LOCK_TTL): Promise<boolean> {
    if (redis) {
        const result = await redis.set(`mutex:${key}`, '1', {
            nx: true,
            px: ttl
        });
        return result === 'OK';
    }
    return upstashAcquireLock(key, ttl);
}

export async function upstashReleaseLock(key: string) {
    if (!ENV.REDIS_REST_TOKEN || !ENV.REDIS_REST_URL) return true;
    try {
        await upstashFetch<any>("pipeline", [["del", `mutex:${key}`]]);
    } catch (e) {
        console.warn("[Mutex] upstash release error", e);
    }
}

export async function releaseLock(key: string): Promise<void> {
    if (redis) {
        await redis.del(`mutex:${key}`);
        return;
    }
    await upstashReleaseLock(key);
}

export async function withLock<T>(
    key: string,
    fn: () => Promise<T>,
    ttl: number = DEFAULT_LOCK_TTL
): Promise<T> {
    const acquired = await acquireLock(key, ttl);
    if (!acquired) {
        throw new Error(`Could not acquire lock for ${key}`);
    }

    try {
        return await fn();
    } finally {
        await releaseLock(key);
    }
}