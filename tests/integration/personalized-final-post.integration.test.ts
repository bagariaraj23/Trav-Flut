import { beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { randomUUID } from "crypto";
import { MediaType, ThreadEntryType, TripStatus } from "@prisma/client";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createTrip, createUser, getAuthToken } from "../testUtils";
import { POST as endTripRoute } from "../../src/app/api/trips/[id]/end/route";
import {
  GET as getFinalPostRoute,
  PUT as updateFinalPostRoute,
} from "../../src/app/api/trips/[id]/final-post/route";
import { POST as generateFinalPostRoute } from "../../src/app/api/trips/[id]/final-post/generate/route";
import { POST as publishFinalPostRoute } from "../../src/app/api/trips/[id]/publish/route";
import { GET as getTripRoute } from "../../src/app/api/trips/[id]/route";
import { GET as getFeedRoute } from "../../src/app/api/feed/home/route";

function authRequest(url: string, method: string, token?: string, body?: unknown) {
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

describe("Personalized final posts", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("gives every member their own post, photos, and publish action", async () => {
    const owner = await createUser({
      email: "final-owner@test.com",
      name: "Owner",
    });
    const member = await createUser({
      email: "final-member@test.com",
      name: "Member",
    });
    const stranger = await createUser({
      email: "final-stranger@test.com",
      name: "Stranger",
    });
    const ownerToken = await getAuthToken(owner);
    const memberToken = await getAuthToken(member);
    const strangerToken = await getAuthToken(stranger);

    const trip = await createTrip({
      userId: owner.id,
      title: "Shared coast",
      status: TripStatus.ONGOING,
    });
    await prisma.tripParticipant.create({
      data: { tripId: trip.id, userId: member.id },
    });

    const ownerPhoto = "https://cdn.example.com/owner-photo.jpg";
    const memberPhoto = "https://cdn.example.com/member-photo.jpg";
    const taggedPhoto = "https://cdn.example.com/member-in-photo.jpg";
    const ownerMedia = await prisma.media.create({
      data: {
        url: ownerPhoto,
        publicId: `owner-${randomUUID()}`,
        type: MediaType.IMAGE,
        uploadedById: owner.id,
        tripId: trip.id,
      },
    });
    const memberMedia = await prisma.media.create({
      data: {
        url: memberPhoto,
        publicId: `member-${randomUUID()}`,
        type: MediaType.IMAGE,
        uploadedById: member.id,
        tripId: trip.id,
      },
    });
    await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: owner.id,
        type: ThreadEntryType.MEDIA,
        mediaId: ownerMedia.id,
        contentText: "The owner watched the tide come in along the rocks.",
      },
    });
    await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: member.id,
        type: ThreadEntryType.TEXT,
        contentText: "I walked the same beach and kept my own notes about the light.",
      },
    });
    await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: member.id,
        type: ThreadEntryType.MEDIA,
        mediaId: memberMedia.id,
      },
    });
    const taggedMedia = await prisma.media.create({
      data: {
        url: taggedPhoto,
        publicId: `tagged-${randomUUID()}`,
        type: MediaType.IMAGE,
        uploadedById: owner.id,
        tripId: trip.id,
      },
    });
    const taggedEntry = await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: owner.id,
        type: ThreadEntryType.MEDIA,
        mediaId: taggedMedia.id,
      },
    });
    await prisma.tripThreadTag.create({
      data: {
        threadEntryId: taggedEntry.id,
        taggedUserId: member.id,
      },
    });

    const params = { params: Promise.resolve({ id: trip.id }) };
    const ended = await json(
      await endTripRoute(
        authRequest(`http://localhost/api/trips/${trip.id}/end`, "POST", ownerToken),
        params
      )
    );
    expect(ended.success).toBe(true);
    expect(ended.data.finalPost.userId).toBe(owner.id);
    expect(ended.data.finalPost.curatedMedia).toEqual([ownerPhoto, taggedPhoto]);
    expect(ended.data.finalPost.curatedMedia).not.toContain(memberPhoto);

    const posts = await prisma.tripFinalPost.findMany({
      where: { tripId: trip.id },
      orderBy: { userId: "asc" },
    });
    expect(posts.map((post) => post.userId).sort()).toEqual(
      [owner.id, member.id].sort()
    );

    const memberDraft = await json(
      await getFinalPostRoute(
        authRequest(
          `http://localhost/api/trips/${trip.id}/final-post`,
          "GET",
          memberToken
        ),
        params
      )
    );
    expect(memberDraft.success).toBe(true);
    expect(memberDraft.data.userId).toBe(member.id);
    expect(memberDraft.data.curatedMedia).toEqual([memberPhoto, taggedPhoto]);
    expect(memberDraft.data.summaryText.toLowerCase()).not.toContain(
      "the owner watched"
    );
    expect(memberDraft.data.isPublished).toBe(false);

    const memberTrip = await json(
      await getTripRoute(
        authRequest(`http://localhost/api/trips/${trip.id}`, "GET", memberToken),
        params
      )
    );
    expect(memberTrip.data.finalPost.userId).toBe(member.id);
    expect(memberTrip.data.finalPost.curatedMedia).toEqual([
      memberPhoto,
      taggedPhoto,
    ]);

    const summary =
      "My own recap of the coast, with the photo I took and nobody else's pictures mixed in.";
    const updated = await json(
      await updateFinalPostRoute(
        authRequest(
          `http://localhost/api/trips/${trip.id}/final-post`,
          "PUT",
          memberToken,
          {
            summaryText: summary,
            curatedMedia: [ownerPhoto, memberPhoto],
            caption: "Mine",
          }
        ),
        params
      )
    );
    expect(updated.success).toBe(true);
    expect(updated.data.summaryText).toBe(summary);
    expect(updated.data.curatedMedia).toEqual([ownerPhoto, memberPhoto]);

    const strangerGenerate = await json(
      await generateFinalPostRoute(
        authRequest(
          `http://localhost/api/trips/${trip.id}/final-post/generate`,
          "POST",
          strangerToken
        ),
        params
      )
    );
    expect(strangerGenerate.success).toBe(false);

    const published = await json(
      await publishFinalPostRoute(
        authRequest(
          `http://localhost/api/trips/${trip.id}/publish`,
          "POST",
          memberToken
        ),
        params
      )
    );
    expect(published.success).toBe(true);
    expect(published.data.userId).toBe(member.id);
    expect(published.data.isPublished).toBe(true);

    const ownerStillDraft = await prisma.tripFinalPost.findUnique({
      where: { tripId_userId: { tripId: trip.id, userId: owner.id } },
    });
    expect(ownerStillDraft?.isPublished).toBe(false);

    const feed = await json(
      await getFeedRoute(
        authRequest("http://localhost/api/feed/home", "GET", strangerToken)
      )
    );
    const memberPost = feed.data.items.find(
      (item: { userId: string }) => item.userId === member.id
    );
    expect(memberPost).toBeTruthy();
    expect(memberPost.curatedMedia).toEqual([ownerPhoto, memberPhoto]);
    expect(memberPost.user.id).toBe(member.id);
    expect(
      feed.data.items.find((item: { userId: string }) => item.userId === owner.id)
    ).toBeUndefined();

    const editedAgain = await json(
      await updateFinalPostRoute(
        authRequest(
          `http://localhost/api/trips/${trip.id}/final-post`,
          "PUT",
          memberToken,
          { caption: "Updated after publishing" }
        ),
        params
      )
    );
    expect(editedAgain.success).toBe(true);
    expect(editedAgain.data.caption).toBe("Updated after publishing");
    expect(editedAgain.data.isPublished).toBe(true);
  });
});
