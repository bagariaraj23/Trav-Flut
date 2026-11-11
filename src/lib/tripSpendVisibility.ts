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

type TripSpendFields = {
  totalSpendMinor?: number;
  spendVisibleOnDiscover?: boolean | null;
};

export function omitHiddenTripSpend<T extends object>(
  trip: T,
  viewerIsMember: boolean
): T {
  const spend = trip as T & TripSpendFields;
  if (
    tripSpendVisibleToViewer({
      viewerIsMember,
      spendVisibleOnDiscover: spend.spendVisibleOnDiscover,
    })
  ) {
    return trip;
  }
  if (!Object.prototype.hasOwnProperty.call(trip, "totalSpendMinor")) {
    return trip;
  }
  const copy: T & TripSpendFields = { ...spend };
  delete copy.totalSpendMinor;
  return copy;
}
