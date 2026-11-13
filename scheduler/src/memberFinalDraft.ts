/**
 * Personal final-post draft shared by the API and the scheduler.
 * A draft is not published. The member edits it and publishes it themselves.
 * The scheduler compiles this file in its own program, so it stays free of the API package.
 */

const MS_IN_DAY = 1000 * 60 * 60 * 24;
export const MIN_SUMMARY_LENGTH = 50;
export const MAX_CURATED_MEDIA = 12;

export type DraftMedia = {
  url: string | null;
  type: string | null;
  processingStatus?: string | null;
  uploadedById: string;
};

export type DraftEntry = {
  authorId: string;
  contentText: string | null;
  createdAt: Date;
  locationName: string | null;
  media: DraftMedia | null;
  taggedUserIds: string[];
  placeName: string | null;
};

export type DraftTrip = {
  title: string | null;
  startDate: Date;
  endDate: Date | null;
  destinations: string[];
  mood: string | null;
  entries: DraftEntry[];
  uploadedMedia: DraftMedia[];
};

export type MemberFinalDraft = {
  summaryText: string;
  curatedMedia: string[];
  caption: string;
  coverMediaUrl: string | null;
  generationStatus: "DRAFT";
};

export function buildMemberFinalDraft(
  trip: DraftTrip,
  userId: string
): MemberFinalDraft {
  const curatedMedia = selectCuratedMedia(trip, userId);
  return {
    summaryText: buildSummary(trip, userId),
    curatedMedia,
    caption: generateDefaultCaption(trip, userId),
    coverMediaUrl: curatedMedia[0] ?? null,
    generationStatus: "DRAFT",
  };
}

function ownEntries(trip: DraftTrip, userId: string) {
  return trip.entries.filter((entry) => entry.authorId === userId);
}

function buildSummary(trip: DraftTrip, userId: string) {
  const durationDays = Math.max(
    1,
    Math.round(
      ((trip.endDate ?? trip.startDate).getTime() - trip.startDate.getTime()) /
        MS_IN_DAY
    ) + 1
  );
  const destinations = trip.destinations ?? [];
  const entries = ownEntries(trip, userId);
  const locationSet = new Set<string>();

  entries.forEach((entry) => {
    if (entry.placeName) {
      locationSet.add(entry.placeName);
    } else if (entry.locationName) {
      locationSet.add(entry.locationName);
    }
  });

  const highlightedLocations = Array.from(locationSet).slice(0, 3);
  const textEntries = entries
    .filter((entry) => entry.contentText)
    .sort(
      (a, b) => (b.contentText?.length ?? 0) - (a.contentText?.length ?? 0)
    )
    .slice(0, 2)
    .map((entry) => `“${truncate(entry.contentText!, 160)}”`);

  const tripTitle = trip.title?.trim() ?? "";
  const destinationLabel =
    destinations.length > 1
      ? `${destinations.length} places`
      : destinations.length === 1
        ? destinations[0]!
        : tripTitle || "your trip";

  const opening =
    destinations.length === 0
      ? `${tripTitle || "Your trip"} was your ${durationDays}-day trip.`
      : `${tripTitle || destinationLabel} was your ${durationDays}-day trip through ${destinationLabel}.`;

  const summaryParts = [
    opening,
    highlightedLocations.length
      ? `Your highlights included ${highlightedLocations.join(", ")}.`
      : "This recap uses the notes and photos you added yourself.",
    textEntries.join(" "),
  ].filter(Boolean);

  let summary = summaryParts.join(" ").trim();
  if (summary.length < MIN_SUMMARY_LENGTH) {
    summary = `${summary} Edit it, keep your own photos, and publish when it feels like yours.`;
  }
  return summary.trim();
}

function selectCuratedMedia(trip: DraftTrip, userId: string) {
  const own = mediaFromEntries(
    trip.entries.filter((entry) => postedOrUploadedBy(entry, userId))
  );
  const tagged = mediaFromEntries(
    trip.entries.filter(
      (entry) =>
        !postedOrUploadedBy(entry, userId) && entryIncludesUser(entry, userId)
    )
  );

  const selected = takePhotos(own);
  for (const url of takePhotos(tagged)) {
    if (selected.length >= MAX_CURATED_MEDIA) break;
    if (!selected.includes(url)) selected.push(url);
  }

  for (const media of trip.uploadedMedia) {
    if (selected.length >= MAX_CURATED_MEDIA) break;
    if (media.uploadedById !== userId) continue;
    const url = usableImageUrl(media);
    if (url && !selected.includes(url)) selected.push(url);
  }

  return selected;
}

function postedOrUploadedBy(entry: DraftEntry, userId: string) {
  return entry.authorId === userId || entry.media?.uploadedById === userId;
}

function entryIncludesUser(entry: DraftEntry, userId: string) {
  return entry.taggedUserIds.some((taggedUserId) => taggedUserId === userId);
}

function mediaFromEntries(entries: DraftEntry[]) {
  return entries.flatMap((entry) => {
    const url = usableImageUrl(entry.media);
    return url ? [{ url, createdAt: entry.createdAt }] : [];
  });
}

function takePhotos(items: { url: string; createdAt: Date }[]) {
  const selected: string[] = [];
  const perDay = new Set<string>();
  const extras: string[] = [];
  const sorted = [...items].sort(
    (a, b) => a.createdAt.getTime() - b.createdAt.getTime()
  );

  for (const item of sorted) {
    const dayKey = item.createdAt.toISOString().substring(0, 10);
    if (!perDay.has(dayKey) && selected.length < MAX_CURATED_MEDIA) {
      selected.push(item.url);
      perDay.add(dayKey);
    } else if (!selected.includes(item.url)) {
      extras.push(item.url);
    }
  }

  for (const url of extras) {
    if (selected.length >= MAX_CURATED_MEDIA) break;
    if (!selected.includes(url)) selected.push(url);
  }

  return selected;
}

function usableImageUrl(media: DraftMedia | null) {
  if (
    !media?.url ||
    media.type !== "IMAGE" ||
    media.processingStatus === "FAILED"
  ) {
    return null;
  }
  return media.url;
}

function generateDefaultCaption(trip: DraftTrip, userId: string) {
  const ownPlace = ownEntries(trip, userId).find(
    (entry) => entry.placeName || entry.locationName
  );
  const primaryDestination =
    ownPlace?.placeName?.trim() ||
    ownPlace?.locationName?.trim() ||
    trip.destinations[0]?.trim() ||
    trip.title?.trim() ||
    "your trip";
  const mood = trip.mood ? `#${trip.mood.toLowerCase()}` : "";
  return [`#${sanitizeTag(primaryDestination)}`, mood].filter(Boolean).join(" ");
}

function sanitizeTag(input: string) {
  return input
    .trim()
    .replace(/\s+/g, "")
    .replace(/[^a-zA-Z0-9]/g, "");
}

function truncate(value: string, limit: number) {
  if (value.length <= limit) {
    return value;
  }
  return `${value.slice(0, limit - 1)}…`;
}
