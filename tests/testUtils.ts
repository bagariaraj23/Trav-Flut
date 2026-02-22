import { prisma } from "../src/lib/prisma";
import { AuthService } from "../src/lib/auth";
import { TripMood, TripStatus, TripType } from "@prisma/client";
import { randomUUID } from "crypto";

/**
 * Safety guard: refuse to wipe DB unless we're in test mode and using TEST_DATABASE_URL.
 * - NODE_ENV must be "test"
 * - Must use TEST_DATABASE_URL from .env.test (mapped to DATABASE_URL in setupTests.ts)
 * - URL must contain "test"/"localhost"/"127.0.0.1" as additional safety check
 */
function assertTestDatabase() {
  // Must be in test mode
  if (process.env.NODE_ENV !== "test") {
    throw new Error(
      "Refusing to clean DB: NODE_ENV is not 'test'. Tests must run with NODE_ENV=test."
    );
  }

  // Must have TEST_DATABASE_URL set (this is the source of truth for tests)
  if (!process.env.TEST_DATABASE_URL) {
    throw new Error(
      "Refusing to clean DB: TEST_DATABASE_URL is not set. Tests require TEST_DATABASE_URL in .env.test."
    );
  }

  // DATABASE_URL should match TEST_DATABASE_URL (set by setupTests.ts)
  const url = process.env.DATABASE_URL;
  if (!url) {
    throw new Error(
      "Refusing to clean DB: DATABASE_URL is not set. This should be set by setupTests.ts from TEST_DATABASE_URL."
    );
  }

  // Additional safety: URL should look like a test database
  const lowered = url.toLowerCase();
  const looksTesty =
    lowered.includes("test") ||
    lowered.includes("localhost") ||
    lowered.includes("127.0.0.1");

  if (!looksTesty) {
    throw new Error(
      `Refusing to clean DB: DATABASE_URL (${url}) does not look like a test database. ` +
        `Test database URLs should contain 'test', 'localhost', or '127.0.0.1'.`
    );
  }

  // Verify DATABASE_URL matches TEST_DATABASE_URL (safety check)
  if (url !== process.env.TEST_DATABASE_URL) {
    throw new Error(
      `Refusing to clean DB: DATABASE_URL (${url}) does not match TEST_DATABASE_URL (${process.env.TEST_DATABASE_URL}). ` +
        `This indicates a configuration error in setupTests.ts.`
    );
  }
}

// Wipe database tables in dependency-safe order for isolation between tests.
export async function cleanDb() {
  assertTestDatabase();
  await prisma.$transaction([
    prisma.notification.deleteMany(),
    prisma.comment.deleteMany(),
    prisma.like.deleteMany(),
    prisma.share.deleteMany(),
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

  // Create user in a transaction to ensure atomicity
  const user = await prisma.$transaction(async (tx) => {
    return tx.user.create({
      data: {
        email,
        username,
        name: overrides.name ?? "Test User",
        password: hashed,
      },
    });
  });

  let verified = false;
  const maxVerificationAttempts = 5;
  const verificationDelays = [5, 10, 20, 40, 80]; // ms

  for (let attempt = 0; attempt < maxVerificationAttempts; attempt++) {
    const result = await prisma.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM users WHERE id = ${user.id} LIMIT 1
    `;

    if (result.length > 0) {
      verified = true;
      break;
    }

    // Wait before next attempt (except on last attempt)
    if (attempt < maxVerificationAttempts - 1) {
      await new Promise((resolve) =>
        setTimeout(resolve, verificationDelays[attempt])
      );
    }
  }

  if (!verified) {
    throw new Error(
      `User ${user.id} was created but is not visible after commit. ` +
        `This indicates a serious database transaction isolation issue.`
    );
  }

  return user;
}

export async function createTrip(
  overrides: Partial<{
    userId: string;
    title: string;
    status: TripStatus;
  }> = {}
) {
  let ownerId: string;

  if (overrides.userId) {
    // Verify user exists using raw SQL
    // This ensures we're querying committed data, not cached data
    const ownerResult = await prisma.$queryRaw<Array<{ id: string }>>`
      SELECT id FROM users WHERE id = ${overrides.userId} LIMIT 1
    `;

    if (ownerResult.length === 0) {
      throw new Error(
        `User with id ${overrides.userId} does not exist. ` +
          `Create the user first using createUser() before creating a trip. ` +
          `Note: createUser() now verifies user visibility before returning, so this should be rare.`
      );
    }
    ownerId = overrides.userId;
  } else {
    const owner = await createUser();
    ownerId = owner.id;
  }

  // Create trip - user is guaranteed to exist and be visible
  // (createUser() now verifies visibility before returning)
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
  const fullUser = await prisma.user.findUnique({
    where: { id: user.id },
    select: { id: true, email: true },
  });
  if (!fullUser) {
    throw new Error(`User ${user.id} not found`);
  }

  // Generate token - the middleware has a 1-second buffer to handle timing differences
  return AuthService.generateAccessToken(fullUser as any);
}

/**
 * Create a final post for testing engagement features
 */
export async function createFinalPost(
  overrides: Partial<{
    tripId: string;
    userId: string;
    isPublished: boolean;
  }> = {}
) {
  let trip;

  if (overrides.tripId) {
    trip = await prisma.trip.findUnique({ where: { id: overrides.tripId } });
    if (!trip) {
      throw new Error(`Trip ${overrides.tripId} not found`);
    }
  } else if (overrides.userId) {
    trip = await createTrip({
      userId: overrides.userId,
      status: TripStatus.ENDED,
    });
  } else {
    const user = await createUser();
    trip = await createTrip({ userId: user.id, status: TripStatus.ENDED });
  }

  return prisma.tripFinalPost.create({
    data: {
      tripId: trip.id,
      summaryText: `Final post summary for testing engagement features. This is a longer summary to meet any validation requirements. ${randomUUID().slice(
        0,
        6
      )}`,
      curatedMedia: [],
      isPublished: overrides.isPublished ?? true,
      generationStatus: overrides.isPublished === false ? "DRAFT" : "PUBLISHED",
    },
  });
}

/**
 * Create a thread entry for testing engagement features
 */
export async function createThreadEntry(
  overrides: Partial<{
    tripId: string;
    userId: string;
  }> = {}
) {
  let trip;

  if (overrides.tripId) {
    trip = await prisma.trip.findUnique({ where: { id: overrides.tripId } });
    if (!trip) {
      throw new Error(`Trip ${overrides.tripId} not found`);
    }
  } else if (overrides.userId) {
    trip = await createTrip({
      userId: overrides.userId,
      status: TripStatus.ONGOING,
    });
  } else {
    const user = await createUser();
    trip = await createTrip({ userId: user.id, status: TripStatus.ONGOING });
  }

  return prisma.tripThreadEntry.create({
    data: {
      tripId: trip.id,
      authorId: trip.userId,
      type: "TEXT",
      contentText: `Thread entry for testing ${randomUUID().slice(0, 6)}`,
    },
  });
}

/**
 * Create a comment for testing
 */
export async function createComment(
  overrides: Partial<{
    userId: string;
    entityType: "TRIP_FINAL_POST" | "TRIP_THREAD_ENTRY" | "COMMENT";
    entityId: string;
    contentText: string;
    parentCommentId?: string;
  }> = {}
) {
  let userId = overrides.userId;

  if (!userId) {
    const user = await createUser();
    userId = user.id;
  }

  // If no entityId provided, create a final post
  let entityId = overrides.entityId;
  let entityType = overrides.entityType || "TRIP_FINAL_POST";

  if (!entityId) {
    const post = await createFinalPost({ userId });
    entityId = post.id;
    entityType = "TRIP_FINAL_POST";
  }

  return prisma.comment.create({
    data: {
      userId,
      entityType,
      entityId,
      contentText:
        overrides.contentText ?? `Test comment ${randomUUID().slice(0, 6)}`,
      parentCommentId: overrides.parentCommentId,
    },
  });
}
