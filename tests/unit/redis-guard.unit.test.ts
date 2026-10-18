import { afterEach, describe, expect, it } from "vitest";
import {
  isRedisCircuitOpen,
  resetRedisCircuitForTests,
  withRedisDeadline,
} from "@/lib/redisGuard";

describe("redis circuit breaker", () => {
  afterEach(() => {
    resetRedisCircuitForTests();
  });

  it("opens after a timed-out Redis call and fails the next call immediately", async () => {
    await expect(
      withRedisDeadline(() => new Promise(() => {}))
    ).rejects.toThrow(/redis_timeout/);

    expect(isRedisCircuitOpen()).toBe(true);

    const started = Date.now();
    await expect(withRedisDeadline(async () => "ok")).rejects.toThrow(
      /redis_circuit_open/
    );
    expect(Date.now() - started).toBeLessThan(100);
  });
});
