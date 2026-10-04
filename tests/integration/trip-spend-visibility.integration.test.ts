import { beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { TripStatus } from "@prisma/client";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createTrip, createUser, getAuthToken } from "../testUtils";
import { GET as getTripRoute } from "../../src/app/api/trips/[id]/route";
import { GET as getFeedRoute } from "../../src/app/api/feed/home/route";
import { GET as getDiscoverRoute } from "../../src/app/api/discover/trips/route";
import { GET as getProfileTripsRoute } from "../../src/app/api/users/[id]/trips/route";
import { PATCH as patchSettingsRoute } from "../../src/app/api/trips/[id]/expense-settings/route";

function authGet(url: string, token: string) {
  return new NextRequest(url, {
    headers: { authorization: `Bearer ${token}` },
  });
}

async function json(response: Response) {
  const text = await response.text();
  return text ? JSON.parse(text) : null;
}

describe("public trip spend", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("hides the spend total from outsiders until the owner opts in", async () => {
    const owner = await createUser({ email: "spend-owner@test.com", name: "Owner" });
    const member = await createUser({ email: "spend-member@test.com", name: "Member" });
    const stranger = await createUser({ email: "spend-stranger@test.com", name: "Stranger" });
    const trip = await createTrip({
      userId: owner.id,
      title: "Hidden spend",
      status: TripStatus.ONGOING,
    });
    await prisma.tripParticipant.create({
      data: { tripId: trip.id, userId: member.id },
    });
    await prisma.trip.update({
      where: { id: trip.id },
      data: { totalSpendMinor: 180000, participantCount: 2 },
    });
    await prisma.tripFinalPost.create({
      data: {
        tripId: trip.id,
        summaryText: "We went",
        curatedMedia: [],
        isPublished: true,
        publishedAt: new Date(),
      },
    });

    const ownerToken = await getAuthToken(owner);
    const memberToken = await getAuthToken(member);
    const strangerToken = await getAuthToken(stranger);

    const strangerTrip = await json(
      await getTripRoute(
        authGet(`http://localhost/api/trips/${trip.id}`, strangerToken),
        { params: Promise.resolve({ id: trip.id }) }
      )
    );
    expect(strangerTrip.success).toBe(true);
    expect(strangerTrip.data).not.toHaveProperty("totalSpendMinor");

    const memberTrip = await json(
      await getTripRoute(
        authGet(`http://localhost/api/trips/${trip.id}`, memberToken),
        { params: Promise.resolve({ id: trip.id }) }
      )
    );
    expect(memberTrip.data.totalSpendMinor).toBe(180000);

    const ownerTrip = await json(
      await getTripRoute(
        authGet(`http://localhost/api/trips/${trip.id}`, ownerToken),
        { params: Promise.resolve({ id: trip.id }) }
      )
    );
    expect(ownerTrip.data.totalSpendMinor).toBe(180000);

    const strangerFeed = await json(
      await getFeedRoute(authGet("http://localhost/api/feed/home?limit=20", strangerToken))
    );
    const strangerPost = strangerFeed.data.items.find(
      (item: { tripId: string }) => item.tripId === trip.id
    );
    expect(strangerPost).toBeTruthy();
    expect(strangerPost.trip).not.toHaveProperty("totalSpendMinor");

    const ownerFeed = await json(
      await getFeedRoute(authGet("http://localhost/api/feed/home?limit=20", ownerToken))
    );
    const ownerPost = ownerFeed.data.items.find(
      (item: { tripId: string }) => item.tripId === trip.id
    );
    expect(ownerPost.trip.totalSpendMinor).toBe(180000);

    const discover = await json(
      await getDiscoverRoute(
        authGet("http://localhost/api/discover/trips?limit=20", strangerToken)
      )
    );
    const discovered = discover.data.items.find(
      (item: { id: string }) => item.id === trip.id
    );
    expect(discovered).toBeTruthy();
    expect(discovered).not.toHaveProperty("totalSpendMinor");

    const profile = await json(
      await getProfileTripsRoute(
        authGet(`http://localhost/api/users/${owner.id}/trips`, strangerToken),
        { params: Promise.resolve({ id: owner.id }) }
      )
    );
    const listed = profile.data.find((item: { id: string }) => item.id === trip.id);
    expect(listed).not.toHaveProperty("totalSpendMinor");

    const memberProfile = await json(
      await getProfileTripsRoute(
        authGet(`http://localhost/api/users/${owner.id}/trips`, memberToken),
        { params: Promise.resolve({ id: owner.id }) }
      )
    );
    const memberListed = memberProfile.data.find(
      (item: { id: string }) => item.id === trip.id
    );
    expect(memberListed.totalSpendMinor).toBe(180000);

    const optedIn = await patchSettingsRoute(
      new NextRequest(`http://localhost/api/trips/${trip.id}/expense-settings`, {
        method: "PATCH",
        headers: {
          authorization: `Bearer ${ownerToken}`,
          "content-type": "application/json",
        },
        body: JSON.stringify({ spendVisibleOnDiscover: true }),
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(optedIn.status).toBe(200);

    const publicTrip = await json(
      await getTripRoute(
        authGet(`http://localhost/api/trips/${trip.id}`, strangerToken),
        { params: Promise.resolve({ id: trip.id }) }
      )
    );
    expect(publicTrip.data.totalSpendMinor).toBe(180000);

    const publicDiscover = await json(
      await getDiscoverRoute(
        authGet("http://localhost/api/discover/trips?limit=20", strangerToken)
      )
    );
    const publicCard = publicDiscover.data.items.find(
      (item: { id: string }) => item.id === trip.id
    );
    expect(publicCard.totalSpendMinor).toBe(180000);
  });
});
