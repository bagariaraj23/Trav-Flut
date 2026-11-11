import { describe, expect, it } from "vitest";
import {
  omitHiddenTripSpend,
  tripSpendVisibleToViewer,
} from "../../src/lib/tripSpendVisibility";

describe("trip spend visibility", () => {
  const trip = {
    id: "trip-1",
    title: "Goa",
    totalSpendMinor: 250000,
    spendVisibleOnDiscover: false,
    expenseCurrency: "INR",
  };

  it("shows the amount to a member even when discover visibility is off", () => {
    expect(
      tripSpendVisibleToViewer({
        viewerIsMember: true,
        spendVisibleOnDiscover: false,
      })
    ).toBe(true);
    const visible = omitHiddenTripSpend(trip, true);
    expect(visible.totalSpendMinor).toBe(250000);
    expect(visible.expenseCurrency).toBe("INR");
  });

  it("shows the amount to a non-member only after the owner opts in", () => {
    expect(
      tripSpendVisibleToViewer({
        viewerIsMember: false,
        spendVisibleOnDiscover: false,
      })
    ).toBe(false);
    expect(
      tripSpendVisibleToViewer({
        viewerIsMember: false,
        spendVisibleOnDiscover: true,
      })
    ).toBe(true);

    const hidden = omitHiddenTripSpend(trip, false);
    expect(hidden).not.toHaveProperty("totalSpendMinor");
    expect(hidden.expenseCurrency).toBe("INR");
    expect(hidden.title).toBe("Goa");

    const optedIn = omitHiddenTripSpend(
      { ...trip, spendVisibleOnDiscover: true },
      false
    );
    expect(optedIn.totalSpendMinor).toBe(250000);
  });

  it("leaves a payload alone when it never carried a spend total", () => {
    const plain = { id: "trip-2", title: "Home" };
    expect(omitHiddenTripSpend(plain, false)).toEqual(plain);
  });
});
