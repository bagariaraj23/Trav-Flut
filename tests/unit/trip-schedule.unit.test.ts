import { describe, expect, it } from "vitest";
import { TripStatus, TripType } from "@prisma/client";
import {
  nextTripStatus,
  resolveAutoTripType,
  endIsLater,
  resolveTripType,
  scheduledEndInstant,
} from "../../src/lib/tripSchedule";

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

  it("ends a chosen time when it is reached and a bare date at 11:59 PM", () => {
    const endOfDay = scheduledEndInstant(
      new Date("2026-03-19T18:30:00.000Z"),
      "Asia/Kolkata"
    );
    expect(endOfDay.toISOString()).toBe("2026-03-20T18:29:59.999Z");

    const chosen = new Date("2026-03-20T13:00:00.000Z");
    expect(scheduledEndInstant(chosen, "Asia/Kolkata").toISOString()).toBe(
      chosen.toISOString()
    );

    const trip = {
      status: TripStatus.ONGOING,
      startDate: istStart,
      endDate: new Date("2026-03-19T18:30:00.000Z"),
      scheduleTimezone: "Asia/Kolkata",
    };
    expect(
      nextTripStatus(trip, new Date("2026-03-20T18:29:59.998Z"))
    ).toBeNull();
    expect(nextTripStatus(trip, endOfDay)).toBe(TripStatus.ENDED);

    const dated = {
      status: TripStatus.ONGOING,
      startDate: new Date("2026-03-20T00:00:00.000Z"),
      endDate: chosen,
      scheduleTimezone: "Asia/Kolkata",
    };
    expect(
      nextTripStatus(dated, new Date("2026-03-20T12:59:00.000Z"))
    ).toBeNull();
    expect(nextTripStatus(dated, chosen)).toBe(TripStatus.ENDED);

    const midnight = new Date("2026-03-19T18:30:00.000Z");
    expect(
      nextTripStatus(
        {
          status: TripStatus.UPCOMING,
          startDate: midnight,
          endDate: midnight,
          scheduleTimezone: "Asia/Kolkata",
        },
        new Date("2026-03-20T04:30:00.000Z")
      )
    ).toBe(TripStatus.ONGOING);
  });

  it("extends a timezone-less UTC midnight end through 11:59 PM UTC", () => {
    const trip = {
      status: TripStatus.ONGOING,
      startDate: new Date("2026-03-19T00:00:00.000Z"),
      endDate: new Date("2026-03-20T00:00:00.000Z"),
    };
    expect(
      nextTripStatus(trip, new Date("2026-03-20T00:00:00.000Z"))
    ).toBeNull();
    expect(
      nextTripStatus(trip, new Date("2026-03-20T23:59:59.999Z"))
    ).toBe(TripStatus.ENDED);
  });
});

describe("endIsLater", () => {
  it("accepts a later end and rejects one that is not after the current end", () => {
    const midnight = new Date("2026-03-19T18:30:00.000Z");
    const earlierThatDay = new Date("2026-03-20T13:00:00.000Z");
    const nextDay = new Date("2026-03-20T18:30:00.000Z");
    expect(endIsLater(midnight, earlierThatDay, "Asia/Kolkata")).toBe(false);
    expect(endIsLater(midnight, nextDay, "Asia/Kolkata")).toBe(true);
    expect(
      endIsLater(
        earlierThatDay,
        new Date("2026-03-20T15:00:00.000Z"),
        "Asia/Kolkata"
      )
    ).toBe(true);
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

describe("resolveTripType", () => {
  it("keeps Couple and Family only when the user specified them", () => {
    expect(
      resolveTripType({
        participantCount: 2,
        typeSetByUser: true,
        currentType: TripType.COUPLE,
      })
    ).toBe(TripType.COUPLE);
    expect(
      resolveTripType({
        participantCount: 1,
        typeSetByUser: true,
        currentType: TripType.COUPLE,
      })
    ).toBe(TripType.COUPLE);
    expect(
      resolveTripType({
        participantCount: 4,
        typeSetByUser: true,
        currentType: TripType.FAMILY,
      })
    ).toBe(TripType.FAMILY);

    expect(
      resolveTripType({
        participantCount: 2,
        typeSetByUser: false,
        currentType: TripType.COUPLE,
      })
    ).toBe(TripType.GROUP);
    expect(
      resolveTripType({
        participantCount: 1,
        typeSetByUser: false,
        currentType: TripType.FAMILY,
      })
    ).toBe(TripType.SOLO);
    expect(
      resolveTripType({
        participantCount: 2,
        typeSetByUser: false,
        currentType: null,
      })
    ).toBe(TripType.GROUP);
  });
});
