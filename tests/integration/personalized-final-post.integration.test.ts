import { describe, it, expect, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { GET as getFinalPostRoute } from "../../src/app/api/trips/[id]/final-post/route";
import { POST as publishFinalPostRoute } from "../../src/app/api/trips/[id]/publish/route";
import {
  cleanDb,
  createUser,
  createTrip,
  getAuthToken,
} from "../testUtils";
import { prisma } from "../../src/lib/prisma";
import { TripStatus } from "@prisma/client";

function createAuthenticatedRequest(
  url: string,
  method: string = "GET",
  body?: any,
  token?: string
): NextRequest {
  return new NextRequest(url, {
    method,
    headers: {
      "content-type": "application/json",
      ...(token ? { authorization: `Bearer ${token}` } : {}),
    },
    ...(body ? { body: JSON.stringify(body) } : {}),
  });
}

async function getResponseData(response: Response): Promise<any> {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

describe("Personalized Final Post API", () => {
  let owner: any;
  let participant: any;
  let ownerToken: string;
  let participantToken: string;
  let trip: any;

  beforeEach(async () => {
    await cleanDb();
    owner = await createUser({ email: "owner@finalpost.test" });
    participant = await createUser({ email: "participant@finalpost.test" });
    ownerToken = await getAuthToken(owner);
    participantToken = await getAuthToken(participant);

    trip = await createTrip({
      userId: owner.id,
      status: TripStatus.ENDED,
    });

    await prisma.tripParticipant.create({
      data: {
        tripId: trip.id,
        userId: participant.id,
      },
    });
  });

  it("generates separate final post drafts for each participant", async () => {
    const ownerReq = createAuthenticatedRequest(
      `http://localhost/api/trips/${trip.id}/final-post`,
      "GET",
      undefined,
      ownerToken
    );
    const ownerRes = await getFinalPostRoute(ownerReq, {
      params: Promise.resolve({ id: trip.id }),
    });
    const ownerData = await getResponseData(ownerRes);

    const participantReq = createAuthenticatedRequest(
      `http://localhost/api/trips/${trip.id}/final-post`,
      "GET",
      undefined,
      participantToken
    );
    const participantRes = await getFinalPostRoute(participantReq, {
      params: Promise.resolve({ id: trip.id }),
    });
    const participantData = await getResponseData(participantRes);

    expect(ownerRes.status).toBe(200);
    expect(participantRes.status).toBe(200);
    expect(ownerData.data.id).not.toBe(participantData.data.id);
    expect(ownerData.data.userId).toBe(owner.id);
    expect(participantData.data.userId).toBe(participant.id);
  });

  it("publishes only the current participant's final post", async () => {
    const participantGetReq = createAuthenticatedRequest(
      `http://localhost/api/trips/${trip.id}/final-post`,
      "GET",
      undefined,
      participantToken
    );
    await getFinalPostRoute(participantGetReq, {
      params: Promise.resolve({ id: trip.id }),
    });

    const publishReq = createAuthenticatedRequest(
      `http://localhost/api/trips/${trip.id}/publish`,
      "POST",
      undefined,
      participantToken
    );
    const publishRes = await publishFinalPostRoute(publishReq, {
      params: Promise.resolve({ id: trip.id }),
    });
    const publishData = await getResponseData(publishRes);

    expect(publishRes.status).toBe(200);
    expect(publishData.data.userId).toBe(participant.id);
    expect(publishData.data.isPublished).toBe(true);

    const posts = await prisma.tripFinalPost.findMany({
      where: { tripId: trip.id },
      orderBy: { userId: "asc" },
    });
    expect(posts.length).toBe(1);
    expect(posts[0].userId).toBe(participant.id);
    expect(posts[0].isPublished).toBe(true);
  });
});
