/**
 * Trip spend is stored on the trip row for members and an optional discover
 * filter. Public payloads must not include the amount unless the owner has
 * opted in, or the viewer is on the trip.
 */
export function tripSpendVisibleToViewer(options: {
  viewerIsMember: boolean;
  spendVisibleOnDiscover?: boolean | null;
}): boolean {
  return options.viewerIsMember || options.spendVisibleOnDiscover === true;
}

export function omitHiddenTripSpend<
  T extends {
    totalSpendMinor?: number;
    spendVisibleOnDiscover?: boolean | null;
  },
>(trip: T, viewerIsMember: boolean): T {
  if (
    tripSpendVisibleToViewer({
      viewerIsMember,
      spendVisibleOnDiscover: trip.spendVisibleOnDiscover,
    })
  ) {
    return trip;
  }
  if (!Object.prototype.hasOwnProperty.call(trip, "totalSpendMinor")) {
    return trip;
  }
  const copy = { ...trip };
  delete copy.totalSpendMinor;
  return copy;
}
