import { describe, it, expect, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser, createTrip, getAuthToken } from "../testUtils";
import { EntityType, ShareType, TripStatus } from "@prisma/client";

import { POST as createLikeRoute } from "../../src/app/api/likes/route";
import { DELETE as deleteLikeRoute } from "../../src/app/api/likes/[entityType]/[entityId]/route";
import { GET as getLikesByEntityRoute } from "../../src/app/api/likes/[entityType]/[entityId]/users/route";
import { GET as getUserLikesRoute } from "../../src/app/api/likes/user/[userId]/route";
import { GET as checkLikeStatusRoute } from "../../src/app/api/likes/status/route";

import { POST as createCommentRoute } from "../../src/app/api/comments/route";
import { GET as getCommentsByEntityRoute } from "../../src/app/api/comments/entity/[entityType]/[entityId]/route";
import { PUT as updateCommentRoute, DELETE as deleteCommentRoute } from "../../src/app/api/comments/[commentId]/route";
import { GET as getCommentRepliesRoute } from "../../src/app/api/comments/[commentId]/replies/route";
import { POST as likeCommentRoute } from "../../src/app/api/comments/[commentId]/like/route";

import { POST as createShareRoute } from "../../src/app/api/shares/route";
import { GET as resolveShareTokenRoute } from "../../src/app/api/shares/[shareToken]/route";
import { POST as trackShareOpenRoute } from "../../src/app/api/shares/track/[shareToken]/route";
import { GET as getSharesByUserRoute } from "../../src/app/api/shares/user/[userId]/route";
import { GET as getShareStatsRoute } from "../../src/app/api/shares/stats/[entityType]/[entityId]/route";

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

function createRequestWithParams(
  baseUrl: string,
  params: Record<string, string>,
  method: string = "GET",
  body?: any,
  token?: string
): NextRequest {
  let url = baseUrl;
  for (const [key, value] of Object.entries(params)) {
    url = url.replace(`[${key}]`, value);
  }
  return createAuthenticatedRequest(url, method, body, token);
}

async function getResponseData(response: Response) {
  const text = await response.text();
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

describe("Engagement API - Likes", () => {
  let user1: any;
  let user2: any;
  let trip: any;
  let finalPost: any;
  let threadEntry: any;
  let token1: string;
  let token2: string;

  beforeEach(async () => {
    await cleanDb();
    user1 = await createUser({ email: "user1@test.com" });
    user2 = await createUser({ email: "user2@test.com" });
    token1 = await getAuthToken(user1);
    token2 = await getAuthToken(user2);

    trip = await createTrip({ userId: user1.id, status: TripStatus.ONGOING });
    finalPost = await prisma.tripFinalPost.create({
      data: {
        tripId: trip.id,
        summaryText: "Test trip summary",
        curatedMedia: [],
        isPublished: true,
      },
    });
    threadEntry = await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: user1.id,
        type: "TEXT",
        contentText: "Test entry",
      },
    });
  });

  describe("POST /api/likes", () => {
    it("should create a like for a trip final post", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        token1
      );

      const response = await createLikeRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const like = await prisma.like.findFirst({
        where: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      expect(like).toBeTruthy();

      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.likeCount).toBe(1);
    });

    it("should create a like for a thread entry", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "TRIP_THREAD_ENTRY",
          entityId: threadEntry.id,
        },
        token1
      );

      const response = await createLikeRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const updatedEntry = await prisma.tripThreadEntry.findUnique({
        where: { id: threadEntry.id },
      });
      expect(updatedEntry?.likeCount).toBe(1);
    });

    it("should return 401 without authentication", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        }
      );

      const response = await createLikeRoute(req);
      expect(response.status).toBe(401);
    });

    it("should return 400 for invalid entity type", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "INVALID",
          entityId: finalPost.id,
        },
        token1
      );

      const response = await createLikeRoute(req);
      expect(response.status).toBe(400);
    });

    it("should return 404 for non-existent entity", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: "00000000-0000-0000-0000-000000000000",
        },
        token1
      );

      const response = await createLikeRoute(req);
      expect(response.status).toBe(404);
    });

    it("should not create duplicate likes", async () => {
      await createLikeRoute(
        createAuthenticatedRequest(
          "http://localhost/api/likes",
          "POST",
          {
            entityType: "TRIP_FINAL_POST",
            entityId: finalPost.id,
          },
          token1
        )
      );

      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        token1
      );

      const response = await createLikeRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const likes = await prisma.like.findMany({
        where: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      expect(likes.length).toBe(1);
    });
  });

  describe("DELETE /api/likes/[entityType]/[entityId]", () => {
    beforeEach(async () => {
      await prisma.like.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      await prisma.tripFinalPost.update({
        where: { id: finalPost.id },
        data: { likeCount: 1 },
      });
    });

    it("should delete a like", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/likes/[entityType]/[entityId]",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        "DELETE",
        undefined,
        token1
      );

      const response = await deleteLikeRoute(req, {
        params: Promise.resolve({
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const like = await prisma.like.findFirst({
        where: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      expect(like).toBeNull();

      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.likeCount).toBe(0);
    });

    it("should return 404 if like does not exist", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/likes/[entityType]/[entityId]",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        "DELETE",
        undefined,
        token2
      );

      const response = await deleteLikeRoute(req, {
        params: Promise.resolve({
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        }),
      });
      expect(response.status).toBe(404);
    });
  });

  describe("GET /api/likes/[entityType]/[entityId]/users", () => {
    beforeEach(async () => {
      await prisma.like.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
          },
          {
            userId: user2.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
          },
        ],
      });
    });

    it("should get users who liked an entity", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/likes/[entityType]/[entityId]/users",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        "GET"
      );

      const response = await getLikesByEntityRoute(req, {
        params: Promise.resolve({
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.items.length).toBe(2);
      expect(data.data.items[0].user.id).toBeDefined();
    });

    it("should support pagination with cursor", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/likes/[entityType]/[entityId]/users?limit=1",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        "GET"
      );

      const response = await getLikesByEntityRoute(req, {
        params: Promise.resolve({
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.data.items.length).toBe(1);
      expect(data.data.nextCursor).toBeTruthy();
    });
  });

  describe("GET /api/likes/user/[userId]", () => {
    beforeEach(async () => {
      await prisma.like.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
          },
          {
            userId: user1.id,
            entityType: EntityType.TRIP_THREAD_ENTRY,
            entityId: threadEntry.id,
          },
        ],
      });
    });

    it("should get user's likes", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/likes/user/[userId]",
        { userId: user1.id },
        "GET",
        undefined,
        token1
      );

      const response = await getUserLikesRoute(req, {
        params: Promise.resolve({ userId: user1.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.items.length).toBe(2);
    });

    it("should return 403 if accessing another user's likes", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/likes/user/[userId]",
        { userId: user1.id },
        "GET",
        undefined,
        token2
      );

      const response = await getUserLikesRoute(req, {
        params: Promise.resolve({ userId: user1.id }),
      });
      expect(response.status).toBe(403);
    });
  });

  describe("GET /api/likes/status", () => {
    beforeEach(async () => {
      await prisma.like.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
    });

    it("should check like status for multiple entities", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/likes/status?entityType=TRIP_FINAL_POST&entityIds=" +
          `${finalPost.id},00000000-0000-0000-0000-000000000000`,
        "GET",
        undefined,
        token1
      );

      const response = await checkLikeStatusRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data[finalPost.id]).toBe(true);
    });
  });
});

describe("Engagement API - Comments", () => {
  let user1: any;
  let user2: any;
  let trip: any;
  let finalPost: any;
  let threadEntry: any;
  let token1: string;
  let token2: string;

  beforeEach(async () => {
    await cleanDb();
    user1 = await createUser({ email: "user1@test.com" });
    user2 = await createUser({ email: "user2@test.com" });
    token1 = await getAuthToken(user1);
    token2 = await getAuthToken(user2);

    trip = await createTrip({ userId: user1.id, status: TripStatus.ONGOING });
    finalPost = await prisma.tripFinalPost.create({
      data: {
        tripId: trip.id,
        summaryText: "Test trip summary",
        curatedMedia: [],
        isPublished: true,
      },
    });
    threadEntry = await prisma.tripThreadEntry.create({
      data: {
        tripId: trip.id,
        authorId: user1.id,
        type: "TEXT",
        contentText: "Test entry",
      },
    });
  });

  describe("POST /api/comments", () => {
    it("should create a comment on a trip final post", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/comments",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          contentText: "Great trip!",
        },
        token1
      );

      const response = await createCommentRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.contentText).toBe("Great trip!");

      const comment = await prisma.comment.findFirst({
        where: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      expect(comment).toBeTruthy();

      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.commentCount).toBe(1);
    });

    it("should create a reply to a comment", async () => {
      const parentComment = await prisma.comment.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          contentText: "Parent comment",
        },
      });

      const req = createAuthenticatedRequest(
        "http://localhost/api/comments",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          contentText: "Reply comment",
          parentCommentId: parentComment.id,
        },
        token2
      );

      const response = await createCommentRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.parentCommentId).toBe(parentComment.id);
    });

    it("should return 400 for comment too long", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/comments",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          contentText: "a".repeat(251), // Max is 250 characters
        },
        token1
      );

      const response = await createCommentRoute(req);
      expect(response.status).toBe(400);
    });

    it("should return 400 for empty comment", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/comments",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          contentText: "   ",
        },
        token1
      );

      const response = await createCommentRoute(req);
      expect(response.status).toBe(400);
    });
  });

  describe("GET /api/comments/[entityType]/[entityId]", () => {
    beforeEach(async () => {
      await prisma.comment.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            contentText: "Comment 1",
          },
          {
            userId: user2.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            contentText: "Comment 2",
          },
        ],
      });
    });

    it("should get comments for an entity", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/comments/entity/[entityType]/[entityId]",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        "GET"
      );

      const response = await getCommentsByEntityRoute(req, {
        params: Promise.resolve({
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.items.length).toBe(2);
    });
  });

  describe("PUT /api/comments/[commentId]", () => {
    let comment: any;

    beforeEach(async () => {
      comment = await prisma.comment.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          contentText: "Original comment",
        },
      });
    });

    it("should update a comment", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/comments/[commentId]",
        { commentId: comment.id },
        "PUT",
        { contentText: "Updated comment" },
        token1
      );

      const response = await updateCommentRoute(req, {
        params: Promise.resolve({ commentId: comment.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.contentText).toBe("Updated comment");

      const updated = await prisma.comment.findUnique({
        where: { id: comment.id },
      });
      expect(updated?.contentText).toBe("Updated comment");
    });

    it("should return 403 if user is not the author", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/comments/[commentId]",
        { commentId: comment.id },
        "PUT",
        { contentText: "Updated comment" },
        token2
      );

      const response = await updateCommentRoute(req, {
        params: Promise.resolve({ commentId: comment.id }),
      });
      expect(response.status).toBe(403);
    });
  });

  describe("DELETE /api/comments/[commentId]", () => {
    let comment: any;

    beforeEach(async () => {
      comment = await prisma.comment.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          contentText: "Comment to delete",
        },
      });
      await prisma.tripFinalPost.update({
        where: { id: finalPost.id },
        data: { commentCount: 1 },
      });
    });

    it("should delete a comment by author", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/comments/[commentId]",
        { commentId: comment.id },
        "DELETE",
        undefined,
        token1
      );

      const response = await deleteCommentRoute(req, {
        params: Promise.resolve({ commentId: comment.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const deleted = await prisma.comment.findUnique({
        where: { id: comment.id },
      });
      expect(deleted).toBeNull();

      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.commentCount).toBe(0);
    });

    it("should delete a comment by entity owner", async () => {
      const commentByUser2 = await prisma.comment.create({
        data: {
          userId: user2.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          contentText: "Comment by user2",
        },
      });
      await prisma.tripFinalPost.update({
        where: { id: finalPost.id },
        data: { commentCount: 1 },
      });

      const req = createRequestWithParams(
        "http://localhost/api/comments/[commentId]",
        { commentId: commentByUser2.id },
        "DELETE",
        undefined,
        token1
      );

      const response = await deleteCommentRoute(req, {
        params: Promise.resolve({ commentId: commentByUser2.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
    });
  });

  describe("GET /api/comments/[commentId]/replies", () => {
    let parentComment: any;

    beforeEach(async () => {
      parentComment = await prisma.comment.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          contentText: "Parent comment",
        },
      });
      await prisma.comment.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            contentText: "Reply 1",
            parentCommentId: parentComment.id,
          },
          {
            userId: user2.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            contentText: "Reply 2",
            parentCommentId: parentComment.id,
          },
        ],
      });
    });

    it("should get replies to a comment", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/comments/[commentId]/replies",
        { commentId: parentComment.id },
        "GET"
      );

      const response = await getCommentRepliesRoute(req, {
        params: Promise.resolve({ commentId: parentComment.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.items.length).toBe(2);
    });
  });

  describe("POST /api/comments/[commentId]/like", () => {
    let comment: any;

    beforeEach(async () => {
      comment = await prisma.comment.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          contentText: "Comment to like",
        },
      });
    });

    it("should like a comment", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/comments/[commentId]/like",
        { commentId: comment.id },
        "POST",
        undefined,
        token2
      );

      const response = await likeCommentRoute(req, {
        params: Promise.resolve({ commentId: comment.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const like = await prisma.like.findFirst({
        where: {
          userId: user2.id,
          entityType: EntityType.COMMENT,
          entityId: comment.id,
        },
      });
      expect(like).toBeTruthy();
    });
  });
});

describe("Engagement API - Shares", () => {
  let user1: any;
  let user2: any;
  let trip: any;
  let finalPost: any;
  let token1: string;
  let token2: string;

  beforeEach(async () => {
    await cleanDb();
    user1 = await createUser({ email: "user1@test.com" });
    user2 = await createUser({ email: "user2@test.com" });
    token1 = await getAuthToken(user1);
    token2 = await getAuthToken(user2);

    trip = await createTrip({ userId: user1.id, status: TripStatus.ONGOING });
    finalPost = await prisma.tripFinalPost.create({
      data: {
        tripId: trip.id,
        summaryText: "Test trip summary",
        curatedMedia: [],
        isPublished: true,
      },
    });
  });

  describe("POST /api/shares", () => {
    it("should create a share", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/shares",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          shareType: "DEEP_LINK",
        },
        token1
      );

      const response = await createShareRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.shareToken).toBeDefined();
      expect(data.data.entityType).toBe("TRIP_FINAL_POST");

      const share = await prisma.share.findFirst({
        where: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      expect(share).toBeTruthy();

      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.shareCount).toBe(0);
    });

    it("should increment shareCount only for IN_APP_DM shareSource", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/shares",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          shareType: "DEEP_LINK",
          shareSource: "IN_APP_DM",
        },
        token1
      );

      const response = await createShareRoute(req);
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.shareCount).toBe(1);
    });

    it("should return 404 for non-existent entity", async () => {
      const req = createAuthenticatedRequest(
        "http://localhost/api/shares",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: "00000000-0000-0000-0000-000000000000",
          shareType: "DEEP_LINK",
        },
        token1
      );

      const response = await createShareRoute(req);
      expect(response.status).toBe(404);
    });
  });

  describe("GET /api/shares/[shareToken]", () => {
    let share: any;

    beforeEach(async () => {
      share = await prisma.share.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          shareToken: "test-token-123",
          shareType: ShareType.DEEP_LINK,
          metadata: {},
        },
      });
    });

    it("should resolve a share token", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/shares/[shareToken]",
        { shareToken: share.shareToken },
        "GET"
      );

      const response = await resolveShareTokenRoute(req, {
        params: Promise.resolve({ shareToken: share.shareToken }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.share).toBeDefined();
      expect(data.data.entity).toBeDefined();
    });

    it("should return 404 for invalid token", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/shares/[shareToken]",
        { shareToken: "invalid-token" },
        "GET"
      );

      const response = await resolveShareTokenRoute(req, {
        params: Promise.resolve({ shareToken: "invalid-token" }),
      });
      expect(response.status).toBe(404);
    });
  });

  describe("POST /api/shares/track/[shareToken]", () => {
    let share: any;

    beforeEach(async () => {
      share = await prisma.share.create({
        data: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
          shareToken: "test-token-456",
          shareType: ShareType.DEEP_LINK,
          metadata: {},
        },
      });
    });

    it("should track share open", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/shares/track/[shareToken]",
        { shareToken: share.shareToken },
        "POST",
        {
          platform: "ios",
          location: "US",
        }
      );

      const response = await trackShareOpenRoute(req, {
        params: Promise.resolve({ shareToken: share.shareToken }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);

      const updated = await prisma.share.findUnique({
        where: { id: share.id },
      });
      const metadata = updated?.metadata as any;
      expect(metadata.opens).toBeDefined();
      expect(metadata.opens.length).toBe(1);
    });
  });

  describe("GET /api/shares/user/[userId]", () => {
    beforeEach(async () => {
      await prisma.share.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            shareToken: "token-1",
            shareType: ShareType.DEEP_LINK,
            metadata: {},
          },
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            shareToken: "token-2",
            shareType: ShareType.WEB_LINK,
            metadata: {},
          },
        ],
      });
    });

    it("should get user's shares", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/shares/user/[userId]",
        { userId: user1.id },
        "GET",
        undefined,
        token1
      );

      const response = await getSharesByUserRoute(req, {
        params: Promise.resolve({ userId: user1.id }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.items.length).toBe(2);
    });

    it("should return 403 if accessing another user's shares", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/shares/user/[userId]",
        { userId: user1.id },
        "GET",
        undefined,
        token2
      );

      const response = await getSharesByUserRoute(req, {
        params: Promise.resolve({ userId: user1.id }),
      });
      expect(response.status).toBe(403);
    });
  });

  describe("GET /api/shares/stats/[entityType]/[entityId]", () => {
    beforeEach(async () => {
      await prisma.share.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            shareToken: "token-1",
            shareType: ShareType.DEEP_LINK,
            metadata: { opens: [{ timestamp: new Date().toISOString() }] },
          },
          {
            userId: user2.id,
            entityType: EntityType.TRIP_FINAL_POST,
            entityId: finalPost.id,
            shareToken: "token-2",
            shareType: ShareType.WEB_LINK,
            metadata: { opens: [{ timestamp: new Date().toISOString() }] },
          },
        ],
      });
      await prisma.tripFinalPost.update({
        where: { id: finalPost.id },
        data: { shareCount: 2 },
      });
    });

    it("should get share stats", async () => {
      const req = createRequestWithParams(
        "http://localhost/api/shares/stats/[entityType]/[entityId]",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        "GET"
      );

      const response = await getShareStatsRoute(req, {
        params: Promise.resolve({
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        }),
      });
      const data = await getResponseData(response);

      expect(response.status).toBe(200);
      expect(data.success).toBe(true);
      expect(data.data.shareCount).toBe(2);
      expect(data.data.metadata).toBeDefined();
    });
  });
});

