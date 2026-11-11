import { describe, it, expect, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { ThreadEntryType, TripStatus } from "@prisma/client";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createTrip, createUser, getAuthToken } from "../testUtils";
import { POST as leaveTripRoute } from "../../src/app/api/trips/[id]/leave/route";

function createAuthenticatedRequest(
  url: string,
  body: unknown,
  token?: string
): NextRequest {
  const headers = new Headers();
  headers.set("Content-Type", "application/json");
  if (token) headers.set("authorization", `Bearer ${token}`);

  return new NextRequest(url, {
    method: "POST",
    headers,
    body: JSON.stringify(body),
  });
}

async function getResponseData(response: Response) {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

describe("POST /api/trips/[id]/leave", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("removes a participant, decrements participantCount, and clears pending invites", async () => {
    const owner = await createUser({ email: "leave-owner@test.com" });
    const participant = await createUser({ email: "leave-participant@test.com" });
    const trip = await createTrip({
      userId: owner.id,
      status: TripStatus.ONGOING,
    });
    const token = await getAuthToken(participant);

    await prisma.tripParticipant.create({
      data: { tripId: trip.id, userId: participant.id },
    });
    await prisma.trip.update({
      where: { id: trip.id },
      data: { participantCount: 2 },
    });
    await prisma.tripJoinRequest.create({
      data: {
        tripId: trip.id,
        senderId: owner.id,
        receiverId: participant.id,
        status: "PENDING",
      },
    });

    const response = await leaveTripRoute(
      createAuthenticatedRequest(
        `http://localhost/api/trips/${trip.id}/leave`,
        { removeMyData: false },
        token
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const data = await getResponseData(response);

    expect(response.status).toBe(200);
    expect(data.success).toBe(true);
    await expect(
      prisma.tripParticipant.findUnique({
        where: { tripId_userId: { tripId: trip.id, userId: participant.id } },
      })
    ).resolves.toBeNull();
    await expect(
      prisma.tripJoinRequest.count({
        where: { tripId: trip.id, receiverId: participant.id },
      })
    ).resolves.toBe(0);
    await expect(
      prisma.trip.findUnique({ where: { id: trip.id } })
    ).resolves.toMatchObject({ participantCount: 1 });
  });

  it("purges only the leaving participant's thread entries when removeMyData is true", async () => {
    const owner = await createUser({ email: "purge-owner@test.com" });
    const participant = await createUser({ email: "purge-participant@test.com" });
    const trip = await createTrip({
      userId: owner.id,
      status: TripStatus.ONGOING,
    });
    const token = await getAuthToken(participant);

    await prisma.tripParticipant.create({
      data: { tripId: trip.id, userId: participant.id },
    });
    await prisma.trip.update({
      where: { id: trip.id },
      data: { participantCount: 2 },
    });
    const ownerEntry = await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: owner.id,
        type: ThreadEntryType.TEXT,
        contentText: "Owner entry should remain",
      },
    });
    const participantEntry = await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: participant.id,
        type: ThreadEntryType.TEXT,
        contentText: "Participant entry should be removed",
      },
    });

    const response = await leaveTripRoute(
      createAuthenticatedRequest(
        `http://localhost/api/trips/${trip.id}/leave`,
        { removeMyData: true },
        token
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const data = await getResponseData(response);

    expect(response.status).toBe(200);
    expect(data.message).toContain("entries were removed");
    await expect(
      prisma.tripThreadEntry.findUnique({ where: { id: ownerEntry.id } })
    ).resolves.toBeTruthy();
    await expect(
      prisma.tripThreadEntry.findUnique({ where: { id: participantEntry.id } })
    ).resolves.toBeNull();
  });

  it("rejects owner leave attempts and removeMyData on ended trips", async () => {
    const owner = await createUser({ email: "owner-denied@test.com" });
    const participant = await createUser({ email: "ended-denied@test.com" });
    const trip = await createTrip({ userId: owner.id, status: TripStatus.ENDED });
    const ownerToken = await getAuthToken(owner);
    const participantToken = await getAuthToken(participant);

    await prisma.tripParticipant.create({
      data: { tripId: trip.id, userId: participant.id },
    });

    const ownerResponse = await leaveTripRoute(
      createAuthenticatedRequest(
        `http://localhost/api/trips/${trip.id}/leave`,
        { removeMyData: false },
        ownerToken
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );
    const participantResponse = await leaveTripRoute(
      createAuthenticatedRequest(
        `http://localhost/api/trips/${trip.id}/leave`,
        { removeMyData: true },
        participantToken
      ),
      { params: Promise.resolve({ id: trip.id }) }
    );

    expect(ownerResponse.status).toBe(400);
    expect((await getResponseData(ownerResponse)).error).toContain(
      "Trip owners cannot leave"
    );
    expect(participantResponse.status).toBe(400);
    expect((await getResponseData(participantResponse)).error).toContain(
      "only be removed while the trip is ongoing"
    );
  });
});
