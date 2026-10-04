import { getUpstashRateLimitStatus } from "@/lib/cache";

const REDIS_TIMEOUT_MS = 250;
const CIRCUIT_OPEN_MS = 30_000;

let circuitOpenUntil = 0;

export function isRedisCircuitOpen(): boolean {
  if (getUpstashRateLimitStatus().isLimited) return true;
  return Date.now() < circuitOpenUntil;
}

export function noteRedisFailure(): void {
  circuitOpenUntil = Date.now() + CIRCUIT_OPEN_MS;
}

export function resetRedisCircuitForTests(): void {
  circuitOpenUntil = 0;
}

/**
 * Bound a Redis call so a slow or dead Upstash does not stall the request.
 * The first failure opens a short circuit and later calls fail immediately.
 */
export async function withRedisDeadline<T>(op: () => Promise<T>): Promise<T> {
  if (isRedisCircuitOpen()) {
    throw new Error("redis_circuit_open");
  }

  let timer: ReturnType<typeof setTimeout> | undefined;
  try {
    const result = await Promise.race([
      op(),
      new Promise<never>((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("redis_timeout")),
          REDIS_TIMEOUT_MS
        );
      }),
    ]);
    return result;
  } catch (error) {
    noteRedisFailure();
    throw error;
  } finally {
    if (timer) clearTimeout(timer);
  }
}
