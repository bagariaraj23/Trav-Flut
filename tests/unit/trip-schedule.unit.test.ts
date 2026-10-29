import { describe, expect, it } from "vitest";
import { TripStatus, TripType } from "@prisma/client";
import { nextTripStatus, resolveAutoTripType } from "../../src/lib/tripSchedule";

const istStart = new Date("2026-03-20T13:00:00.000Z");

describe("nextTripStatus", () => {
  it("keeps a future start upcoming and starts it at the UTC instant", () => {
    const trip = {
      status: TripStatus.UPCOMING,
      startDate: istStart,
      endDate: null,
    };

    expect(nextTripStatus(trip, new Date("2026-03-20T12:59:00.000Z"))).toBeNull();
    expect(nextTripStatus(trip, istStart)).toBe(TripStatus.ONGOING);
  });

  it("does not auto-end an open trip and ends a scheduled end at that instant", () => {
    const open = {
      status: TripStatus.ONGOING,
      startDate: istStart,
      endDate: null,
    };
    expect(nextTripStatus(open, new Date("2026-04-01T00:00:00.000Z"))).toBeNull();

    const scheduled = {
      status: TripStatus.ONGOING,
      startDate: istStart,
      endDate: new Date("2026-03-20T18:30:00.000Z"),
    };
    expect(
      nextTripStatus(scheduled, new Date("2026-03-20T18:29:00.000Z"))
    ).toBeNull();
    expect(
      nextTripStatus(scheduled, new Date("2026-03-20T18:30:00.000Z"))
    ).toBe(TripStatus.ENDED);
  });
});

describe("resolveAutoTripType", () => {
  it("is Solo alone and Group once someone else joins, never Couple", () => {
    expect(resolveAutoTripType(1)).toBe(TripType.SOLO);
    expect(resolveAutoTripType(2)).toBe(TripType.GROUP);
    expect(resolveAutoTripType(4)).toBe(TripType.GROUP);
    expect(resolveAutoTripType(2)).not.toBe(TripType.COUPLE);
  });
});
