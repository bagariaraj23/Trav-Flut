import { afterEach, describe, expect, it } from "vitest";
import {
  getOrSet,
  invalidateCachedKey,
  memoryCache,
  shouldWaitForPeerCacheFill,
} from "../../src/lib/redis";
import {
  noteRedisFailure,
  resetRedisCircuitForTests,
} from "../../src/lib/redisGuard";

describe("shouldWaitForPeerCacheFill", () => {
  it("waits only when another worker may still be filling Redis", () => {
    expect(
      shouldWaitForPeerCacheFill({
        redisConfigured: true,
        acquiredLock: false,
        circuitOpen: false,
        lockAttemptFailed: false,
      })
    ).toBe(true);
  });

  it("does not wait after this process took the lock", () => {
    expect(
      shouldWaitForPeerCacheFill({
        redisConfigured: true,
        acquiredLock: true,
        circuitOpen: false,
        lockAttemptFailed: false,
      })
    ).toBe(false);
  });

  it("does not wait when Redis is down or this process failed to lock", () => {
    expect(
      shouldWaitForPeerCacheFill({
        redisConfigured: true,
        acquiredLock: false,
        circuitOpen: true,
        lockAttemptFailed: false,
      })
    ).toBe(false);
    expect(
      shouldWaitForPeerCacheFill({
        redisConfigured: true,
        acquiredLock: false,
        circuitOpen: false,
        lockAttemptFailed: true,
      })
    ).toBe(false);
    expect(
      shouldWaitForPeerCacheFill({
        redisConfigured: false,
        acquiredLock: false,
        circuitOpen: false,
        lockAttemptFailed: false,
      })
    ).toBe(false);
  });
});

describe("getOrSet", () => {
  const key = "test:getOrSet:unread";

  afterEach(async () => {
    resetRedisCircuitForTests();
    await invalidateCachedKey(key);
  });

  it("serves a memory hit without calling the getter again", async () => {
    let calls = 0;
    const first = await getOrSet(key, async () => {
      calls += 1;
      return 4;
    }, 60_000);
    const second = await getOrSet(key, async () => {
      calls += 1;
      return 9;
    }, 60_000);

    expect(first).toBe(4);
    expect(second).toBe(4);
    expect(calls).toBe(1);
    expect(memoryCache.get(key)).toBe(4);
  });

  it("does not stall the getter while the Redis circuit is open", async () => {
    noteRedisFailure();
    const started = Date.now();
    const value = await getOrSet(`${key}:open`, async () => 7, 60_000);
    expect(value).toBe(7);
    expect(Date.now() - started).toBeLessThan(400);
    await invalidateCachedKey(`${key}:open`);
  });
});
