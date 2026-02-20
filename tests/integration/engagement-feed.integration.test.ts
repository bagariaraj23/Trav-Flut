import { describe, it, expect, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser, createTrip, getAuthToken } from "../testUtils";
import { EntityType, TripStatus } from "@prisma/client";

import { GET as getFeedRoute } from "../../src/app/api/feed/home/route";
import { GET as getTripEntriesRoute } from "../../src/app/api/trips/[id]/entries/route";

function createAuthenticatedRequest(
  url: string,
  method: string = "GET",
  body?: any,
  token?: string
): NextRequest {
  const headers = new Headers();
  headers.set("Content-Type", "application/json");
  if (token) {
    headers.set("authorization", `Bearer ${token}`);
  }
  return new NextRequest(url, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
}

async function getResponseData(response: Response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

describe("Engagement API - Feed Integration", () => {
  let user1: any;
  let user2: any;
  let trip1: any;
  let trip2: any;
  let finalPost1: any;
  let finalPost2: any;
  let token1: string;
  let token2: string;

  beforeEach(async () => {
    await cleanDb();
    user1 = await createUser({ email: "user1@test.com" });
    user2 = await createUser({ email: "user2@test.com", username: "publicuser" });
    token1 = await getAuthToken(user1);
    token2 = await getAuthToken(user2);

    await prisma.user.update({
      where: { id: user2.id },
      data: { isPrivate: false },
    });

    trip1 = await createTrip({ userId: user1.id, status: TripStatus.ONGOING });
    trip2 = await createTrip({ userId: user2.id, status: TripStatus.ONGOING });

    finalPost1 = await prisma.tripFinalPost.create({
      data: {
        tripId: trip1.id,
        userId: trip1.userId,
        summaryText: "Post 1",
        curatedMedia: [],
        isPublished: true,
      },
    });

    finalPost2 = await prisma.tripFinalPost.create({
      data: {
        tripId: trip2.id,
        userId: trip2.userId,
        summaryText: "Post 2",
        curatedMedia: [],
        isPublished: true,
      },
    });

    await prisma.follow.create({
      data: {
        followerId: user1.id,
        followeeId: user2.id,
      },
    });
  });

  describe("GET /api/feed/home", () => {
    beforeEach(async () => {
      await prisma.like.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost1.id,
          },
          {
            userId: user2.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost1.id,
          },
        ],
      });

      await prisma.comment.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost1.id,
            contentText: "Comment 1",
          },
          {
            userId: user2.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost1.id,
            contentText: "Comment 2",
          },
        ],
      });

      await prisma.share.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost1.id,
          shareToken: "token-1",
          shareType: "DEEP_LINK",
          metadata: {},
        },
      });

      await prisma.tripFinalPost.update({
        where: { id: finalPost1.id },
        data: {
          likeCount: 2,
          commentCount: 2,
          shareCount: 1,
        },
      });
    });

    it("should include engagement data in feed", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/feed/home?page=1&limit=20",
        "GET",
        undefined,
        token1
      );

      const response = await getFeedRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.items.length).toBeGreaterThan(0);

      const post = data.data.items.find((p: any) => p.id === finalPost1.id);
      expect(post).toBeDefined();
      expect(post.likeCount).toBe(2);
      expect(post.commentCount).toBe(2);
      expect(post.shareCount).toBe(1);
      expect(typeof post.hasLiked).toBe("boolean");
    });

    it("should correctly indicate if current user has liked", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/feed/home?page=1&limit=20",
        "GET",
        undefined,
        token1
      );

      const response = await getFeedRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      const post = data.data.items.find((p: any) => p.id === finalPost1.id);
      expect(post.hasLiked).toBe(true);
    });

    it("should correctly indicate if current user has not liked", async () => {
      const user3 = await createUser({ email: "user3@test.com" });
      const token3 = await getAuthToken(user3);

      const req = createAuthenticatedRequest(
        "http://localhost/api/feed/home?page=1&limit=20",
        "GET",
        undefined,
        token3
      );

      const response = await getFeedRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      const post = data.data.items.find((p: any) => p.id === finalPost1.id);
      if (post) {
        expect(post.hasLiked).toBe(false);
      }
    });
  });
});

describe("Engagement API - Trip Entries Integration", () => {
  let user1: any;
  let user2: any;
  let trip: any;
  let entry1: any;
  let entry2: any;
  let token1: string;
  let token2: string;

  beforeEach(async () => {
    await cleanDb();
    user1 = await createUser({ email: "user1@test.com" });
    user2 = await createUser({ email: "user2@test.com" });
    token1 = await getAuthToken(user1);
    token2 = await getAuthToken(user2);

    trip = await createTrip({ userId: user1.id, status: TripStatus.ONGOING });

    entry1 = await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: user1.id,
        type: "TEXT",
        contentText: "Entry 1",
      },
    });

    entry2 = await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: user1.id,
        type: "TEXT",
        contentText: "Entry 2",
      },
    });

    await prisma.like.createMany({
      data: [
        {
          userId: user1.id,
          entityType: EntityType.TRIP_THREAD_ENTRY,
          entityId: entry1.id,
        },
        {
          userId: user2.id,
          entityType: EntityType.TRIP_THREAD_ENTRY,
          entityId: entry1.id,
        },
      ],
    });

    await prisma.comment.createMany({
      data: [
        {
          userId: user1.id,
          entityType: EntityType.TRIP_THREAD_ENTRY,
          entityId: entry1.id,
          contentText: "Comment 1",
        },
        {
          userId: user2.id,
          entityType: EntityType.TRIP_THREAD_ENTRY,
          entityId: entry1.id,
          contentText: "Comment 2",
        },
      ],
    });

    await prisma.tripThreadEntry.update({
      where: { id: entry1.id },
      data: {
        likeCount: 2,
        commentCount: 2,
      },
    });
  });

  describe("GET /api/trips/[id]/entries", () => {
    it("should include engagement data in trip entries", async () => {
      const req = createAuthenticatedRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "GET",
        undefined,
        token1
      );

      const response = await getTripEntriesRoute(req, {
        params: Promise.resolve({ id: trip.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.length).toBe(2);

      const entry = data.data.find((e: any) => e.id === entry1.id);
      expect(entry).toBeDefined();
      expect(entry.likeCount).toBe(2);
      expect(entry.commentCount).toBe(2);
      expect(typeof entry.hasLiked).toBe("boolean");
    });

    it("should correctly indicate if current user has liked entry", async () => {
      const req = createAuthenticatedRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "GET",
        undefined,
        token1
      );

      const response = await getTripEntriesRoute(req, {
        params: Promise.resolve({ id: trip.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      const entry = data.data.find((e: any) => e.id === entry1.id);
      expect(entry.hasLiked).toBe(true);
    });

    it("should correctly indicate if current user has not liked entry", async () => {
      const user3 = await createUser({ email: "user3@test.com" });
      const token3 = await getAuthToken(user3);

      const req = createAuthenticatedRequest(
        `http://localhost/api/trips/${trip.id}/entries`,
        "GET",
        undefined,
        token3
      );

      const response = await getTripEntriesRoute(req, {
        params: Promise.resolve({ id: trip.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      const entry = data.data.find((e: any) => e.id === entry2.id);
      if (entry) {
        expect(entry.hasLiked).toBe(false);
      }
    });
  });
});

