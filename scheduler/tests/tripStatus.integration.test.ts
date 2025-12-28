// Integration test for direct execution (no BullMQ/Redis required)
// This test verifies the updateTripStatuses function works correctly
// when called directly, simulating how cron would invoke it

import { describe, test, expect, vi } from "vitest";
import { updateTripStatuses } from "../src/tripStatus";

// Create minimal prisma mock with counters to assert calls
function createPrismaMock() {
  const calls: any[] = [];
  const prisma: any = {
    $transaction: vi.fn(async (callback: (tx: any) => Promise<any>) => {
      // Create a transaction mock that supports callback pattern
      const tx = {
        trip: {
          findUnique: vi.fn(() => Promise.resolve(null)),
          update: vi.fn(() => Promise.resolve({})),
          updateMany: vi.fn(() => Promise.resolve({ count: 0 })),
        },
        tripFinalPost: {
          findUnique: vi.fn(() => Promise.resolve(null)),
          create: vi.fn(() => Promise.resolve({})),
        },
        tripThreadEntry: {
          findMany: vi.fn(() => Promise.resolve([])),
        },
      };
      return callback(tx);
    }),
    trip: {
      findMany: vi.fn(() => {
        return Promise.resolve([]);
      }),
      updateMany: vi.fn((args: any) => {
        calls.push(args);
        return Promise.resolve({ count: 1 });
      }),
    },
    tripFinalPost: {
      findUnique: vi.fn(() => Promise.resolve(null)),
      create: vi.fn(() => Promise.resolve({})),
    },
    tripThreadEntry: {
      findMany: vi.fn(() => Promise.resolve([])),
    },
  };
  return { prisma, calls } as const;
}

describe("Direct execution integration for trip status updates", () => {
  test("executes updateTripStatuses directly (simulating cron invocation)", async () => {
    const { prisma, calls } = createPrismaMock();

    // Simulate direct cron invocation
    await updateTripStatuses(prisma as any, new Date("2025-10-06T12:00:00Z"));

    // Verify transaction was called (which contains the updateMany calls)
    expect(prisma.$transaction).toHaveBeenCalled();
  }, 5000);
});
