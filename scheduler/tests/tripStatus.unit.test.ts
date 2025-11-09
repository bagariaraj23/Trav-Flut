import { updateTripStatuses, TripStatus } from "../src/tripStatus";

type UpdateManyArgs = any;

function createPrismaMock() {
  const updateManyCalls: UpdateManyArgs[] = [];
  const prisma: any = {
    $transaction: (ops: any[]) => {
      // Execute provided operations to capture payloads
      return Promise.all(
        ops.map((op) => {
          return op.then ? op : op; // support direct client calls
        })
      ) as any;
    },
    trip: {
      updateMany: jest.fn((args: UpdateManyArgs) => {
        updateManyCalls.push(args);
        return Promise.resolve({ count: 0 });
      }),
    },
  };

  return { prisma, updateManyCalls } as const;
}

describe("updateTripStatuses", () => {
  test("sets ENDED when endDate <= now for UPCOMING or ONGOING", async () => {
    const { prisma, updateManyCalls } = createPrismaMock();
    const now = new Date("2025-10-06T12:00:00Z");

    await updateTripStatuses(prisma, now as any);

    expect(prisma.trip.updateMany).toHaveBeenCalledTimes(2);

    const endedCall = updateManyCalls[0];
    expect(endedCall.where).toEqual({
      endDate: { lte: now },
      status: { in: [TripStatus.UPCOMING, TripStatus.ONGOING] },
    });
    expect(endedCall.data).toEqual({ status: TripStatus.ENDED });
  });

  test("sets ONGOING when startDate <= now < endDate and currently UPCOMING", async () => {
    const { prisma, updateManyCalls } = createPrismaMock();
    const now = new Date("2025-10-06T12:00:00Z");

    await updateTripStatuses(prisma, now as any);

    const ongoingCall = updateManyCalls[1];
    expect(ongoingCall.where).toEqual({
      startDate: { lte: now },
      endDate: { gt: now },
      status: TripStatus.UPCOMING,
    });
    expect(ongoingCall.data).toEqual({ status: TripStatus.ONGOING });
  });

  test("time resolution: boundary behavior at exact endDate", async () => {
    const { prisma, updateManyCalls } = createPrismaMock();
    const now = new Date("2025-10-06T00:00:00Z");

    await updateTripStatuses(prisma, now as any);

    const endedCall = updateManyCalls[0];
    expect(endedCall.where.endDate).toEqual({ lte: now });
    // ensures exact equality transitions to ENDED, not ONGOING
    const ongoingCall = updateManyCalls[1];
    expect(ongoingCall.where.endDate).toEqual({ gt: now });
  });
});
