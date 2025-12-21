import { prisma } from "../src/lib/prisma";
import { AuthService } from "../src/lib/auth";
import { TripMood, TripStatus, TripType } from "@prisma/client";
import { randomUUID } from "crypto";

/**
 * Safety guard: refuse to wipe DB unless the URL looks like a test database.
 * - NODE_ENV must be "test" OR the URL must contain "test"/"localhost"/"127.0.0.1".
 * - If TEST_DATABASE_URL is set and differs from DATABASE_URL, we fail fast to avoid
 *   accidentally pointing Prisma at prod.
 */
function assertTestDatabase() {
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error(
      "DATABASE_URL is not set. Refusing to clean DB. Configure a test DB URL."
    );
  }
  const lowered = url.toLowerCase();
  const looksTesty =
    lowered.includes("test") ||
    lowered.includes("localhost") ||
    lowered.includes("127.0.0.1");
  const isTestEnv = process.env.NODE_ENV === "test";

  if (!isTestEnv && !looksTesty) {
    throw new Error(
      "Refusing to clean DB: DATABASE_URL does not look like a test DB. Set NODE_ENV=test and use a test DB URL."
    );
  }

  if (process.env.TEST_DATABASE_URL && process.env.TEST_DATABASE_URL !== url) {
    throw new Error(
      "Refusing to clean DB: TEST_DATABASE_URL differs from DATABASE_URL. Ensure Prisma is using the test DB URL."
    );
  }
}

// Wipe database tables in dependency-safe order for isolation between tests.
export async function cleanDb() {
  assertTestDatabase();
  await prisma.$transaction([
    prisma.tripThreadTag.deleteMany(),
    prisma.tripThreadEntry.deleteMany(),
    prisma.tripFinalPost.deleteMany(),
    prisma.tripJoinRequest.deleteMany(),
    prisma.tripParticipant.deleteMany(),
    prisma.followRequest.deleteMany(),
    prisma.follow.deleteMany(),
    prisma.jWTRefreshToken.deleteMany(),
    prisma.oAuthAccount.deleteMany(),
    prisma.passwordReset.deleteMany(),
    prisma.media.deleteMany(),
    prisma.placeShare.deleteMany(),
    prisma.placeOnTrip.deleteMany(),
    prisma.trip.deleteMany(),
    prisma.user.deleteMany(),
    prisma.place.deleteMany(),
  ]);
}

export async function createUser(
  overrides: Partial<{
    email: string;
    username: string | null;
    name: string | null;
    password: string;
  }> = {}
) {
  const email = overrides.email ?? `test-${randomUUID()}@example.com`;
  const username = overrides.username ?? `user_${randomUUID().slice(0, 8)}`;
  const password = overrides.password ?? "Password123!";
  const hashed = await AuthService.hashPassword(password);

  return prisma.user.create({
    data: {
      email,
      username,
      name: overrides.name ?? "Test User",
      password: hashed,
    },
  });
}

export async function createTrip(
  overrides: Partial<{
    userId: string;
    title: string;
    status: TripStatus;
  }> = {}
) {
  // If userId provided, use it directly (assume user exists - tests should create user first)
  // Otherwise create a new user
  let ownerId: string;
  if (overrides.userId) {
    // Try to find user, but if not found immediately, wait a bit and retry (for test isolation)
    let owner = await prisma.user.findUnique({
      where: { id: overrides.userId },
    });

    // Retry once after a brief delay if user not found (handles transaction isolation in tests)
    if (!owner) {
      await new Promise((resolve) => setTimeout(resolve, 50));
      owner = await prisma.user.findUnique({
        where: { id: overrides.userId },
      });
    }

    if (!owner) {
      throw new Error(
        `User with id ${overrides.userId} does not exist. Create the user first using createUser() before creating a trip.`
      );
    }
    ownerId = overrides.userId;
  } else {
    const owner = await createUser();
    ownerId = owner.id;
  }

  return prisma.trip.create({
    data: {
      userId: ownerId,
      title: overrides.title ?? `Trip ${randomUUID().slice(0, 6)}`,
      destinations: ["Paris"],
      startDate: new Date(),
      endDate: new Date(Date.now() + 86400000),
      status: overrides.status ?? TripStatus.UPCOMING,
      type: TripType.SOLO,
      mood: TripMood.MIXED,
    },
  });
}

export async function getAuthToken(user: { id: string; email?: string }) {
  return AuthService.generateAccessToken({
    id: user.id,
    email: user.email ?? "",
  } as any);
}
