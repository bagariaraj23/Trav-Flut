/**
 * Sample data for the **test database only**.
 *
 * Loads **`.env.test`** and uses **`TEST_DATABASE_URL`** exclusively (never `.env` / production).
 * The database name in that URL must end with `_test` (e.g. `tripthread_test`).
 *
 * Environment:
 * - SEED_RESET=full — delete seed users (and cascaded data), then recreate everything.
 * - Default — delete only trips tagged with SEED_MARKER, then recreate trips/posts/thread data.
 *
 * Demo login (password): TripThreadSeed123!
 */

import dotenv from "dotenv";
import path from "path";
import fs from "fs";
import bcrypt from "bcryptjs";
import type { AppPrismaClient } from "@/lib/prisma";
import { assertTestDatabaseUrl } from "@/lib/dbUrlSafety";
import {
  GenerationStatus,
  PlaceSource,
  PlaceType,
  ThreadEntryType,
  TripMood,
  TripStatus,
  TripType,
} from "@prisma/client";

const SEED_MARKER = "[tripthread-seed-v1]";
/** Demo accounts — safe to wipe when SEED_RESET=full */
const SEED_EMAILS = [
  "demo.alice@tripthread.seed",
  "demo.bob@tripthread.seed",
  "demo.carol@tripthread.seed",
] as const;

const DEMO_PASSWORD = "TripThreadSeed123!";

/** Resolve TEST_DATABASE_URL from `.env.test` only; production URLs are never read. */
function loadSeedEnv(): void {
  const root = process.cwd();
  const envTest = path.join(root, ".env.test");
  if (!fs.existsSync(envTest)) {
    throw new Error(
      "Seed requires `.env.test` with TEST_DATABASE_URL. Production `.env` is intentionally ignored."
    );
  }
  dotenv.config({ path: envTest });
  delete process.env.DATABASE_URL;
  assertTestDatabaseUrl(process.env.TEST_DATABASE_URL, "Seed");
  process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
}

async function wipeSeedTrips(prisma: AppPrismaClient): Promise<void> {
  const deleted = await prisma.trip.deleteMany({
    where: { description: { contains: SEED_MARKER } },
  });
  if (deleted.count > 0) {
    console.log(`Removed ${deleted.count} previous seed trip(s).`);
  }
}

async function wipeSeedUsers(prisma: AppPrismaClient): Promise<void> {
  const deleted = await prisma.user.deleteMany({
    where: { email: { in: [...SEED_EMAILS] } },
  });
  if (deleted.count > 0) {
    console.log(`Removed ${deleted.count} seed user account(s).`);
  }
}

async function seed(prisma: AppPrismaClient): Promise<void> {
  assertTestDatabaseUrl(process.env.DATABASE_URL, "Seed");

  console.log("Starting database seeding…");

  if (process.env.SEED_RESET === "full") {
    await wipeSeedUsers(prisma);
  } else {
    await wipeSeedTrips(prisma);
  }

  const passwordHash = await bcrypt.hash(DEMO_PASSWORD, 12);

  const alice = await prisma.user.upsert({
    where: { email: SEED_EMAILS[0] },
    update: { password: passwordHash },
    create: {
      email: SEED_EMAILS[0],
      username: "alice_demo",
      name: "Alice Demo",
      password: passwordHash,
      isPrivate: false,
    },
  });

  const bob = await prisma.user.upsert({
    where: { email: SEED_EMAILS[1] },
    update: { password: passwordHash },
    create: {
      email: SEED_EMAILS[1],
      username: "bob_demo",
      name: "Bob Demo",
      password: passwordHash,
      isPrivate: false,
    },
  });

  const carol = await prisma.user.upsert({
    where: { email: SEED_EMAILS[2] },
    update: { password: passwordHash },
    create: {
      email: SEED_EMAILS[2],
      username: "carol_demo",
      name: "Carol Demo",
      password: passwordHash,
      isPrivate: false,
    },
  });

  console.log("Users:", {
    alice: alice.username,
    bob: bob.username,
    carol: carol.username,
  });

  await prisma.follow.upsert({
    where: {
      followerId_followeeId: { followerId: alice.id, followeeId: bob.id },
    },
    update: {},
    create: { followerId: alice.id, followeeId: bob.id },
  });

  await prisma.follow.upsert({
    where: {
      followerId_followeeId: { followerId: alice.id, followeeId: carol.id },
    },
    update: {},
    create: { followerId: alice.id, followeeId: carol.id },
  });

  console.log("Follow edges: alice → bob, alice → carol");

  const placeTokyo = await prisma.place.upsert({
    where: { externalId: "seed-place-tokyo" },
    update: {},
    create: {
      name: "Tokyo",
      address: "Tokyo, Japan",
      lat: 35.6762,
      lng: 139.6503,
      placeType: PlaceType.POI,
      source: PlaceSource.MAPBOX,
      externalId: "seed-place-tokyo",
    },
  });

  const placeBali = await prisma.place.upsert({
    where: { externalId: "seed-place-bali" },
    update: {},
    create: {
      name: "Bali",
      address: "Bali, Indonesia",
      lat: -8.409518,
      lng: 115.188919,
      placeType: PlaceType.POI,
      source: PlaceSource.MAPBOX,
      externalId: "seed-place-bali",
    },
  });

  const placeParis = await prisma.place.upsert({
    where: { externalId: "seed-place-paris" },
    update: {},
    create: {
      name: "Paris",
      address: "Paris, France",
      lat: 48.8566,
      lng: 2.3522,
      placeType: PlaceType.POI,
      source: PlaceSource.MAPBOX,
      externalId: "seed-place-paris",
    },
  });

  const seedSuffix = `\n\n${SEED_MARKER}`;

  const tripTokyo = await prisma.trip.create({
    data: {
      userId: bob.id,
      title: "Tokyo Adventure",
      destinations: ["Tokyo, Japan"],
      startDate: new Date(Date.UTC(2024, 0, 15)),
      endDate: new Date(Date.UTC(2024, 0, 22)),
      status: TripStatus.ENDED,
      mood: TripMood.CULTURAL,
      type: TripType.SOLO,
      coverMediaId: null,
      startLocationId: placeTokyo.id,
      endLocationId: placeTokyo.id,
      description:
        "Exploring the vibrant culture, incredible food, and modern marvels of Tokyo." +
        seedSuffix,
    },
  });

  await prisma.placeOnTrip.create({
    data: {
      tripId: tripTokyo.id,
      placeId: placeTokyo.id,
      order: 0,
      dayIndex: 0,
    },
  });

  const tripBali = await prisma.trip.create({
    data: {
      userId: carol.id,
      title: "Bali Escape",
      destinations: ["Bali, Indonesia"],
      startDate: new Date(Date.UTC(2024, 1, 10)),
      endDate: new Date(Date.UTC(2024, 1, 17)),
      status: TripStatus.ENDED,
      mood: TripMood.RELAXED,
      type: TripType.SOLO,
      coverMediaId: null,
      startLocationId: placeBali.id,
      endLocationId: placeBali.id,
      description:
        "Island paradise, temples, and incredible sunsets." + seedSuffix,
    },
  });

  await prisma.placeOnTrip.create({
    data: {
      tripId: tripBali.id,
      placeId: placeBali.id,
      order: 0,
      dayIndex: 0,
    },
  });

  const tripParis = await prisma.trip.create({
    data: {
      userId: bob.id,
      title: "Paris Weekend",
      destinations: ["Paris, France"],
      startDate: new Date(Date.UTC(2026, 4, 10)),
      endDate: new Date(Date.UTC(2026, 4, 25)),
      status: TripStatus.ONGOING,
      mood: TripMood.CULTURAL,
      type: TripType.COUPLE,
      coverMediaId: null,
      startLocationId: placeParis.id,
      endLocationId: placeParis.id,
      participantCount: 2,
      description: "Romantic weekend in the City of Light." + seedSuffix,
    },
  });

  await prisma.placeOnTrip.create({
    data: {
      tripId: tripParis.id,
      placeId: placeParis.id,
      order: 0,
      dayIndex: 0,
    },
  });

  await prisma.tripParticipant.create({
    data: {
      tripId: tripParis.id,
      userId: alice.id,
      role: "member",
    },
  });

  console.log("Trips:", {
    tripTokyo: tripTokyo.title,
    tripBali: tripBali.title,
    tripParis: tripParis.title,
  });

  const publishedAt = new Date();

  await prisma.tripFinalPost.create({
    data: {
      tripId: tripTokyo.id,
      summaryText:
        "An incredible week exploring Tokyo's vibrant culture, incredible food, and modern marvels. From Shibuya Crossing to Senso-ji Temple, every moment was filled with wonder.",
      curatedMedia: [
        "https://images.pexels.com/photos/2506923/pexels-photo-2506923.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/1907228/pexels-photo-1907228.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/1239291/pexels-photo-1239291.jpeg?auto=compress&cs=tinysrgb&w=600",
      ],
      caption: "Tokyo stole my heart 🇯🇵✨",
      generationStatus: GenerationStatus.PUBLISHED,
      isPublished: true,
      publishedAt,
    },
  });

  await prisma.tripFinalPost.create({
    data: {
      tripId: tripBali.id,
      summaryText:
        "A week of pure bliss in Bali. Temples of Ubud, beaches of Nusa Penida — magical sunsets every evening.",
      curatedMedia: [
        "https://images.pexels.com/photos/3073666/pexels-photo-3073666.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/3889843/pexels-photo-3889843.jpeg?auto=compress&cs=tinysrgb&w=600",
        "https://images.pexels.com/photos/3889845/pexels-photo-3889845.jpeg?auto=compress&cs=tinysrgb&w=600",
      ],
      caption: "Bali vibes 🌴☀️",
      generationStatus: GenerationStatus.PUBLISHED,
      isPublished: true,
      publishedAt,
    },
  });

  console.log("Final posts: Tokyo & Bali published.");

  await prisma.tripThreadEntry.createMany({
    data: [
      {
        tripId: tripTokyo.id,
        authorId: bob.id,
        type: ThreadEntryType.TEXT,
        contentText: "Landed in Narita — jet lagged but excited!",
      },
      {
        tripId: tripTokyo.id,
        authorId: bob.id,
        type: ThreadEntryType.TEXT,
        contentText: "Senso-ji at sunrise. Quiet streets before the crowds.",
      },
      {
        tripId: tripBali.id,
        authorId: carol.id,
        type: ThreadEntryType.TEXT,
        contentText: "Ubud rice terraces — unreal greens.",
      },
      {
        tripId: tripParis.id,
        authorId: bob.id,
        type: ThreadEntryType.TEXT,
        contentText: "First café au lait by the Seine.",
      },
      {
        tripId: tripParis.id,
        authorId: alice.id,
        type: ThreadEntryType.TEXT,
        contentText: "Joined Bob — Metro to Montmartre tonight!",
      },
    ],
  });

  await prisma.trip.update({
    where: { id: tripTokyo.id },
    data: { entryCount: 2 },
  });
  await prisma.trip.update({
    where: { id: tripBali.id },
    data: { entryCount: 1 },
  });
  await prisma.trip.update({
    where: { id: tripParis.id },
    data: { entryCount: 2 },
  });

  console.log("Thread entries & entry counts updated.");
  console.log("");
  console.log("Done. Demo password for all seed users:", DEMO_PASSWORD);
  console.log("Emails:", SEED_EMAILS.join(", "));
}

async function main(): Promise<void> {
  loadSeedEnv();
  const { prisma } = await import("@/lib/prisma");
  try {
    await seed(prisma);
  } finally {
    await prisma.$disconnect();
  }
}

main().catch((e: unknown) => {
  const msg = e instanceof Error ? e.message : String(e);
  const code =
    typeof e === "object" && e !== null && "code" in e
      ? String((e as { code?: string }).code ?? "")
      : typeof e === "object" && e !== null && "errorCode" in e
        ? String((e as { errorCode?: string }).errorCode ?? "")
        : "";
  if (code === "P1003" || msg.includes("does not exist")) {
    console.error(
      "Database is missing or unreachable. Create the DB and schema first:\n" +
        "  bash scripts/setup-test-db.sh\n" +
        "Ensure `.env.test` sets TEST_DATABASE_URL to a Postgres URL whose DB name ends with _test."
    );
  } else {
    console.error("Error during seeding:", e);
  }
  process.exit(1);
});
