import { Worker, Queue, Job } from "bullmq";

// We'll import the function to test directly rather than the whole index bootstrap
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
    },
  };
  return { prisma, calls } as const;
}

describe("BullMQ integration for trip status updates", () => {
  const shouldRun = process.env.REDIS_E2E === "1";

  (shouldRun ? test : test.skip)(
    "enqueues and processes a one-off update job (requires Redis at REDIS_URL or localhost:6379)",
    async () => {
      const connectionString =
        process.env.REDIS_URL || "redis://localhost:6379";
      const queue = new Queue("tripStatus", {
        connection: { url: connectionString } as any,
      });
      const { prisma, calls } = createPrismaMock();

      // A tiny worker that invokes our update function on job
      const worker = new Worker(
        "tripStatus",
        async (_job: Job) => {
          await updateTripStatuses(
            prisma as any,
            new Date("2025-10-06T12:00:00Z")
          );
        },
        { connection: { url: connectionString } as any, concurrency: 1 }
      );

      await queue.add("updateTripStatus", {});

      // wait for completion
      await new Promise<void>((resolve, reject) => {
        worker.on("completed", () => resolve());
        worker.on("failed", (err) => reject(err));
      });

      expect(calls.length).toBe(2);

      await worker.close();
      await queue.close();
    },
    15000
  );
});
