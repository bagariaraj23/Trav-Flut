import { describe, expect, test, vi } from "vitest";
import { TripStatus, updateTripStatuses } from "../src/tripStatus";

type TripToEnd = {
  id: string;
  title: string;
  destinations: string[];
};

function createPrismaMock(options: {
  tripsToEnd?: TripToEnd[];
  existingFinalPostTripIds?: string[];
  ongoingCount?: number;
  failTripIds?: string[];
} = {}) {
  const tripsToEnd = options.tripsToEnd ?? [];
  const existing = new Set(options.existingFinalPostTripIds ?? []);
  const failTripIds = new Set(options.failTripIds ?? []);

  const tx = {
    tripFinalPost: {
      findUnique: vi.fn(({ where }: any) =>
        Promise.resolve(existing.has(where.tripId) ? { id: `post-${where.tripId}` } : null)
      ),
      create: vi.fn(({ data }: any) => Promise.resolve({ id: `post-${data.tripId}`, ...data })),
    },
    trip: {
      findUnique: vi.fn(({ where }: any) => {
        const trip = tripsToEnd.find((t) => t.id === where.id);
        if (!trip) return Promise.resolve(null);
        return Promise.resolve({
          ...trip,
          threadEntries: [
            {
              id: `media-entry-${trip.id}`,
              type: "MEDIA",
              mediaId: `media-${trip.id}`,
              media: { url: `https://cdn.example.com/${trip.id}.jpg` },
            },
          ],
        });
      }),
      update: vi.fn(({ where, data }: any) => {
        if (failTripIds.has(where.id)) {
          throw new Error(`forced failure for ${where.id}`);
        }
        return Promise.resolve({ id: where.id, ...data });
      }),
      updateMany: vi.fn(() => Promise.resolve({ count: options.ongoingCount ?? 0 })),
    },
    tripThreadEntry: {
      findMany: vi.fn(({ where }: any) =>
        Promise.resolve([
          {
            id: `text-entry-${where.tripId}`,
            tripId: where.tripId,
            type: "TEXT",
            contentText: "A memorable travel moment",
            createdAt: new Date("2026-01-01T10:00:00.000Z"),
          },
          {
            id: `location-entry-${where.tripId}`,
            tripId: where.tripId,
            type: "LOCATION",
            locationName: "Museum",
            createdAt: new Date("2026-01-01T11:00:00.000Z"),
          },
        ])
      ),
    },
  };

  const prisma = {
    trip: {
      findMany: vi.fn(() => Promise.resolve(tripsToEnd)),
    },
    $transaction: vi.fn((callback: (tx: any) => Promise<unknown>) => callback(tx)),
  };

  return { prisma: prisma as any, tx };
}

describe("updateTripStatuses behavior", () => {
  test("creates a missing final post, ends selected trips, and starts eligible trips", async () => {
    const now = new Date("2026-02-01T00:00:00.000Z");
    const { prisma, tx } = createPrismaMock({
      tripsToEnd: [
        {
          id: "trip-ended",
          title: "Japan",
          destinations: ["Tokyo", "Kyoto"],
        },
      ],
      ongoingCount: 3,
    });

    const result = await updateTripStatuses(prisma, now);

    expect(prisma.trip.findMany).toHaveBeenCalledWith({
      where: {
        endDate: { lte: now },
        status: { in: [TripStatus.UPCOMING, TripStatus.ONGOING] },
      },
      select: { id: true, destinations: true, title: true },
    });
    expect(tx.tripFinalPost.create).toHaveBeenCalledWith(
      expect.objectContaining({
        data: expect.objectContaining({
          tripId: "trip-ended",
          summaryText: expect.stringContaining("Tokyo, Kyoto"),
          curatedMedia: ["https://cdn.example.com/trip-ended.jpg"],
        }),
      })
    );
    expect(tx.trip.update).toHaveBeenCalledWith({
      where: { id: "trip-ended" },
      data: { status: TripStatus.ENDED },
    });
    expect(tx.trip.updateMany).toHaveBeenCalledWith({
      where: {
        startDate: { lte: now },
        endDate: { gt: now },
        status: TripStatus.UPCOMING,
      },
      data: { status: TripStatus.ONGOING },
    });
    expect(result).toEqual({
      nowIso: now.toISOString(),
      endedCount: 1,
      ongoingCount: 3,
    });
  });

  test("does not create a duplicate final post when one already exists", async () => {
    const { prisma, tx } = createPrismaMock({
      tripsToEnd: [{ id: "trip-existing", title: "Peru", destinations: ["Lima"] }],
      existingFinalPostTripIds: ["trip-existing"],
    });

    await updateTripStatuses(prisma, new Date("2026-02-01T00:00:00.000Z"));

    expect(tx.tripFinalPost.findUnique).toHaveBeenCalledWith({
      where: { tripId: "trip-existing" },
    });
    expect(tx.tripFinalPost.create).not.toHaveBeenCalled();
    expect(tx.trip.update).toHaveBeenCalledWith({
      where: { id: "trip-existing" },
      data: { status: TripStatus.ENDED },
    });
  });

  test("continues ending other trips when one trip fails inside its transaction", async () => {
    const errorSpy = vi.spyOn(console, "error").mockImplementation(() => {});
    const { prisma, tx } = createPrismaMock({
      tripsToEnd: [
        { id: "trip-fails", title: "Fail", destinations: ["A"] },
        { id: "trip-succeeds", title: "Success", destinations: ["B"] },
      ],
      failTripIds: ["trip-fails"],
    });

    const result = await updateTripStatuses(
      prisma,
      new Date("2026-02-01T00:00:00.000Z")
    );

    expect(tx.trip.update).toHaveBeenCalledWith({
      where: { id: "trip-fails" },
      data: { status: TripStatus.ENDED },
    });
    expect(tx.trip.update).toHaveBeenCalledWith({
      where: { id: "trip-succeeds" },
      data: { status: TripStatus.ENDED },
    });
    expect(errorSpy).toHaveBeenCalledWith(
      "Failed to end trip trip-fails:",
      "forced failure for trip-fails"
    );
    expect(result.endedCount).toBe(2);
    errorSpy.mockRestore();
  });
});
