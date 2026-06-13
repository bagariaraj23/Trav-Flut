import { beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { randomUUID } from "crypto";
import { MediaType, ThreadEntryType, TripStatus } from "@prisma/client";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createTrip, createUser, getAuthToken } from "../testUtils";
import { POST as createTripRoute } from "../../src/app/api/trips/route";
import { GET as getTripStatusRoute } from "../../src/app/api/trips/status/route";
import { GET as checkConflictsRoute } from "../../src/app/api/trips/check-conflicts/route";
import {
  GET as getEntriesRoute,
  POST as createEntryRoute,
} from "../../src/app/api/trips/[id]/entries/route";
import {
  DELETE as deleteEntryRoute,
  PATCH as patchEntryRoute,
} from "../../src/app/api/trips/[id]/entries/[entryId]/route";

function authRequest(
  url: string,
  method: string,
  token?: string,
  body?: unknown
): NextRequest {
  const headers = new Headers();
  headers.set("Content-Type", "application/json");
  if (token) headers.set("authorization", `Bearer ${token}`);
  return new NextRequest(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
}

async function json(response: Response) {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

function isoDaysFromNow(days: number) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString();
}

async function createPlace(name: string) {
  return prisma.place.create({
    data: {
      name,
      lat: 48.8566,
      lng: 2.3522,
      externalId: `test-${name}-${randomUUID()}`,
    },
  });
}

describe("Trip and thread route flow", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("creates a trip, reports conflict state, and returns current ongoing participant trip", async () => {
    const owner = await createUser({ email: "trip-owner@test.com" });
    const participant = await createUser({ email: "trip-participant@test.com" });
    const ownerToken = await getAuthToken(owner);
    const participantToken = await getAuthToken(participant);
    const firstPlace = await createPlace("Paris");
    const secondPlace = await createPlace("Lyon");

    const createResponse = await createTripRoute(
      authRequest(
        "http://localhost/api/trips",
        "POST",
        ownerToken,
        {
          title: "France Loop",
          description: "Testing full trip creation",
          startDate: isoDaysFromNow(1),
          endDate: isoDaysFromNow(4),
          destinationPlaceIds: [firstPlace.id, secondPlace.id],
          mood: "CULTURAL",
          type: "GROUP",
        }
      )
    );
    const createData = await json(createResponse);

    expect(createResponse.status).toBe(201);
    expect(createData.success).toBe(true);
    expect(createData.data.title).toBe("France Loop");
    expect(createData.data.status).toBe("UPCOMING");
    await expect(
      prisma.placeOnTrip.count({ where: { tripId: createData.data.id } })
    ).resolves.toBe(2);

    const conflictResponse = await checkConflictsRoute(
      authRequest(
        "http://localhost/api/trips/check-conflicts",
        "GET",
        ownerToken
      )
    );
    const conflictData = await json(conflictResponse);

    expect(conflictResponse.status).toBe(200);
    expect(conflictData.data.hasFutureTrip).toBe(true);

    await prisma.tripParticipant.create({
      data: { tripId: createData.data.id, userId: participant.id },
    });
    await prisma.trip.update({
      where: { id: createData.data.id },
      data: { status: TripStatus.ONGOING, participantCount: 2 },
    });

    const statusResponse = await getTripStatusRoute(
      authRequest("http://localhost/api/trips/status", "GET", participantToken)
    );
    const statusData = await json(statusResponse);

    expect(statusResponse.status).toBe(200);
    expect(statusData.success).toBe(true);
    expect(statusData.data.id).toBe(createData.data.id);
  });

  it("creates text/media/location entries, paginates them, edits text, and deletes entries with permissions", async () => {
    const owner = await createUser({ email: "thread-owner@test.com" });
    const participant = await createUser({
      email: "thread-participant@test.com",
      username: "thread_participant",
    });
    const outsider = await createUser({ email: "thread-outsider@test.com" });
    const ownerToken = await getAuthToken(owner);
    const participantToken = await getAuthToken(participant);
    const outsiderToken = await getAuthToken(outsider);
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    const place = await createPlace("Museum");
    const media = await prisma.media.create({
      data: {
        url: "https://cdn.example.com/thread.jpg",
        publicId: `thread-${randomUUID()}`,
        type: MediaType.IMAGE,
        uploadedById: participant.id,
      },
    });
    await prisma.tripParticipant.create({
      data: { tripId: trip.id, userId: participant.id },
    });

    const textResponse = await createEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "POST",
        participantToken,
        {
          type: "TEXT",
          contentText: " first note ",
          taggedUsernames: [owner.username],
        }
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const textData = await json(textResponse);

    expect(textResponse.status).toBe(201);
    expect(textData.data.contentText).toBe("First note");

    const mediaResponse = await createEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "POST",
        participantToken,
        {
          type: "MEDIA",
          mediaId: media.id,
        }
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(mediaResponse.status).toBe(201);
    await expect(
      prisma.media.findUnique({ where: { id: media.id } })
    ).resolves.toMatchObject({ tripId: trip.id });

    const locationResponse = await createEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "POST",
        ownerToken,
        {
          type: "LOCATION",
          placeId: place.id,
        }
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const locationData = await json(locationResponse);

    expect(locationResponse.status).toBe(201);
    expect(locationData.data.locationName).toBe(place.name);

    const pageResponse = await getEntriesRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries?limit=2`,
        "GET",
        ownerToken
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const pageData = await json(pageResponse);

    expect(pageResponse.status).toBe(200);
    expect(pageData.data.items).toHaveLength(2);
    expect(pageData.data.hasMoreOlder).toBe(true);
    expect(pageData.data.nextOlderCursor).toEqual(expect.any(String));

    const forbiddenPatch = await patchEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries/${textData.data.id}`,
        "PATCH",
        outsiderToken,
        { contentText: "hacked" }
      ),
      { params: Promise.resolve({ id: trip.id, entryId: textData.data.id }) }
    );
    expect(forbiddenPatch.status).toBe(403);

    const patchResponse = await patchEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries/${textData.data.id}`,
        "PATCH",
        participantToken,
        { contentText: " updated note " }
      ),
      { params: Promise.resolve({ id: trip.id, entryId: textData.data.id }) }
    );
    const patchData = await json(patchResponse);

    expect(patchResponse.status).toBe(200);
    expect(patchData.data.contentText).toBe("Updated note");

    const deleteResponse = await deleteEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries/${textData.data.id}`,
        "DELETE",
        ownerToken
      ),
      { params: Promise.resolve({ id: trip.id, entryId: textData.data.id }) }
    );

    expect(deleteResponse.status).toBe(200);
    await expect(
      prisma.tripThreadEntry.findUnique({ where: { id: textData.data.id } })
    ).resolves.toBeNull();
  });

  it("rejects thread entry creation for non-participants, ended trips, and invalid media", async () => {
    const owner = await createUser({ email: "reject-owner@test.com" });
    const participant = await createUser({ email: "reject-participant@test.com" });
    const outsider = await createUser({ email: "reject-outsider@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ENDED });
    const ownerToken = await getAuthToken(owner);
    const outsiderToken = await getAuthToken(outsider);
    await prisma.tripParticipant.create({
      data: { tripId: trip.id, userId: participant.id },
    });

    const endedResponse = await createEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "POST",
        ownerToken,
        { type: "TEXT", contentText: "Ended trip entry" }
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(endedResponse.status).toBe(400);

    await prisma.trip.update({
      where: { id: trip.id },
      data: { status: TripStatus.ONGOING },
    });

    const outsiderResponse = await createEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "POST",
        outsiderToken,
        { type: "TEXT", contentText: "Outsider entry" }
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(outsiderResponse.status).toBe(403);

    const mediaResponse = await createEntryRoute(
      authRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "POST",
        ownerToken,
        { type: "MEDIA" }
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(mediaResponse.status).toBe(400);
  });
});
