// Integration test for direct execution (no BullMQ/Redis required)
// This test verifies the updateTripStatuses function works correctly
// when called directly, simulating how cron would invoke it

import { updateTripStatuses } from "../src/tripStatus";

// Create minimal prisma mock with counters to assert calls
function createPrismaMock() {
  const calls: any[] = [];
  const prisma: any = {
    $transaction: (ops: any[]) => Promise.all(ops) as any,
    trip: {
      updateMany: jest.fn((args: any) => {
        calls.push(args);
        return Promise.resolve({ count: 1 });
      }),
      findMany: jest.fn((args: any) => {
        return Promise.resolve([]);
      }),
    },
    tripFinalPost: {
      findUnique: jest.fn(() => Promise.resolve(null)),
      create: jest.fn(() => Promise.resolve({})),
    },
    tripThreadEntry: {
      findMany: jest.fn(() => Promise.resolve([])),
    },
  };
  return { prisma, calls } as const;
}

describe("Direct execution integration for trip status updates", () => {
  test(
    "executes updateTripStatuses directly (simulating cron invocation)",
    async () => {
      const { prisma, calls } = createPrismaMock();

      // Simulate direct cron invocation
      await updateTripStatuses(
        prisma as any,
        new Date("2025-10-06T12:00:00Z")
      );

      // Verify transaction was called (which contains the updateMany calls)
      expect(prisma.$transaction).toHaveBeenCalled();
    },
    5000
  );
});
