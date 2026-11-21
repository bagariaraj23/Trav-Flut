import { MediaType } from "@prisma/client";
import { ValidationError } from "../errors";
import { prisma, type PrismaTransactionClient } from "../prisma";

type DbClient = PrismaTransactionClient | typeof prisma;

const OWN_UPLOAD_TYPES: MediaType[] = [
  MediaType.IMAGE,
  MediaType.GIF,
  MediaType.VIDEO,
];

export const MAX_POST_MEDIA = 12;

/** Photos already stored on this trip, including photos on thread entries. */
export async function tripMediaUrls(db: DbClient, tripId: string) {
  const trip = await db.trip.findUnique({
    where: { id: tripId },
    select: {
      media: { select: { url: true } },
      threadEntries: { select: { media: { select: { url: true } } } },
    },
  });
  const urls = new Set<string>();
  for (const media of trip?.media ?? []) {
    if (media.url) urls.add(media.url);
  }
  for (const entry of trip?.threadEntries ?? []) {
    if (entry.media?.url) urls.add(entry.media.url);
  }
  return urls;
}

/**
 * A final post may use a photo already on the trip, or a photo this person
 * uploaded from their own device. Chat attachments stay out. Another person's
 * Cloudinary URL stays out, even when it uses the same account.
 */
export async function allowedFinalPostUrls(
  db: DbClient,
  tripId: string,
  userId: string,
  candidates: string[]
) {
  const allowed = await tripMediaUrls(db, tripId);
  const wanted = uniqueUrls(candidates);
  if (wanted.length === 0) return allowed;

  const own = await db.media.findMany({
    where: {
      url: { in: wanted },
      uploadedById: userId,
      chatMessageId: null,
      type: { in: OWN_UPLOAD_TYPES },
    },
    select: { url: true },
  });
  for (const row of own) {
    if (row.url) allowed.add(row.url);
  }
  return allowed;
}

/** A direct post can only use media this person uploaded, never a chat file. */
export async function assertAuthorUploads(
  db: DbClient,
  userId: string,
  urls: string[]
) {
  const wanted = uniqueUrls(urls);
  if (wanted.length > MAX_POST_MEDIA) {
    throw new ValidationError(`You can choose up to ${MAX_POST_MEDIA} photos`);
  }
  if (wanted.length === 0) return wanted;

  const own = await db.media.findMany({
    where: {
      url: { in: wanted },
      uploadedById: userId,
      chatMessageId: null,
      type: { in: OWN_UPLOAD_TYPES },
    },
    select: { url: true },
  });
  const found = new Set(own.map((row) => row.url));
  if (wanted.some((url) => !found.has(url))) {
    throw new ValidationError("Upload photos from your phone");
  }
  return wanted;
}

export function uniqueUrls(urls: string[]) {
  const seen = new Set<string>();
  const kept: string[] = [];
  for (const raw of urls) {
    const url = raw?.trim();
    if (!url || seen.has(url)) continue;
    seen.add(url);
    kept.push(url);
  }
  return kept;
}

export async function assertTripUploadAccess(
  db: DbClient,
  userId: string,
  tripId: string
) {
  const trip = await db.trip.findFirst({
    where: {
      id: tripId,
      OR: [
        { userId },
        { participants: { some: { userId } } },
        { finalPosts: { some: { userId } } },
      ],
    },
    select: { id: true },
  });
  return !!trip;
}
