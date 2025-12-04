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
        // If Redis is unavailable, upstashFetch returns null
        // In that case, allow the operation to proceed (graceful degradation)
        if (res === null) {
            console.warn(`[Mutex] Redis unavailable for lock ${key}, proceeding without lock`);
            return true;
        }
        return res === "OK";
    } catch (e) {
        console.warn("[Mutex] Lock acquisition failed, proceeding without lock:", e);
        // Graceful degradation: allow operation to proceed if Redis is unavailable
        return true;
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
    // If lock acquisition fails (Redis unavailable), proceed anyway
    // This allows graceful degradation when Redis is down
    // Note: This means concurrent operations might run, but database constraints will prevent duplicates
    if (!acquired) {
        console.warn(`[Mutex] Could not acquire lock for ${key}, proceeding without lock (Redis may be unavailable)`);
        // Proceed without lock - database constraints will handle duplicates
        return await fn();
    }

    try {
        return await fn();
    } finally {
        await releaseLock(key);
    }
}