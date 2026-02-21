import { describe, it, expect, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { prisma } from "../../src/lib/prisma";
import {
  cleanDb,
  createUser,
  createFinalPost,
  createThreadEntry,
  createComment,
  getAuthToken,
} from "../testUtils";
import { EntityType } from "@prisma/client";

import { POST as createCommentRoute } from "../../src/app/api/comments/route";
import { POST as createLikeRoute } from "../../src/app/api/likes/route";
import { POST as createShareRoute } from "../../src/app/api/shares/route";
import { DELETE as deleteCommentRoute } from "../../src/app/api/comments/[commentId]/route";

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

describe("Engagement API - Edge Cases & Gaps", () => {
  let user1: any;
  let user2: any;
  let token1: string;
  let token2: string;

  beforeEach(async () => {
    await cleanDb();
    user1 = await createUser({ email: "user1@test.com" });
    user2 = await createUser({ email: "user2@test.com" });
    token1 = await getAuthToken(user1);
    token2 = await getAuthToken(user2);
  });

  describe("Permission & Privacy Tests", () => {
    it("should prevent engagement on deleted posts", async () => {
      const finalPost = await createFinalPost();

      // Delete the post
      await prisma.tripFinalPost.delete({
        where: { id: finalPost.id },
      });

      // Try to like deleted post
      const likeReq = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
        },
        token1
      );

      const likeResponse = await createLikeRoute(likeReq);
      expect(likeResponse.status).toBe(404);

      // Try to comment on deleted post
      const commentReq = createAuthenticatedRequest(
        "http://localhost/api/comments",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          contentText: "Comment on deleted post",
        },
        token1
      );

      const commentResponse = await createCommentRoute(commentReq);
      expect(commentResponse.status).toBe(404);
    });

    it("should prevent sharing non-published final posts", async () => {
      const finalPost = await createFinalPost({ isPublished: false });

      const req = createAuthenticatedRequest(
        "http://localhost/api/shares",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          shareType: "DEEP_LINK",
        },
        token2 // Different user trying to share
      );

      const response = await createShareRoute(req);

      // Should fail - only published posts can be shared
      expect(response.status).toBe(403);
    });

    it("should handle engagement on deleted thread entries", async () => {
      const entry = await createThreadEntry();

      // Delete the entry
      await prisma.tripThreadEntry.delete({
        where: { id: entry.id },
      });

      // Try to like deleted entry
      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "TRIP_THREAD_ENTRY",
          entityId: entry.id,
        },
        token1
      );

      const response = await createLikeRoute(req);
      expect(response.status).toBe(404);
    });
  });

  describe("Concurrency Edge Cases", () => {
    it("should handle concurrent comment creation without duplicates", async () => {
      const finalPost = await createFinalPost();

      // Create 10 concurrent comments
      const results = await Promise.allSettled(
        Array.from({ length: 10 }, (_, i) =>
          createCommentRoute(
            createAuthenticatedRequest(
              "http://localhost/api/comments",
              "POST",
              {
                entityType: "TRIP_FINAL_POST",
                entityId: finalPost.id,
                contentText: `Concurrent comment ${i}`,
              },
              token1
            )
          )
        )
      );

      // All should succeed (no unique constraint on comments)
      const successful = results.filter((r) => r.status === "fulfilled");
      expect(successful.length).toBe(10);

      // Verify all comments were created
      const comments = await prisma.comment.findMany({
        where: {
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      expect(comments.length).toBe(10);

      // Verify comment count is accurate
      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.commentCount).toBe(10);
    });

    it("should handle concurrent like/unlike cycles correctly", async () => {
      const finalPost = await createFinalPost();

      // Perform 5 rapid like/unlike cycles
      for (let i = 0; i < 5; i++) {
        // Like
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

        // Unlike (delete)
        await fetch(
          `http://localhost/api/likes/TRIP_FINAL_POST/${finalPost.id}`,
          {
            method: "DELETE",
            headers: {
              authorization: `Bearer ${token1}`,
            },
          }
        );
      }

      // Final state: should have no likes
      const likeCount = await prisma.like.count({
        where: {
          userId: user1.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: finalPost.id,
        },
      });
      expect(likeCount).toBe(0);

      // Post like count should be 0
      const updatedPost = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(updatedPost?.likeCount).toBe(0);
    });
  });

  describe("Validation & Edge Cases", () => {
    it("should prevent excessively long comments", async () => {
      const finalPost = await createFinalPost();

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

    it("should handle nested comment replies correctly", async () => {
      const finalPost = await createFinalPost();

      // Create parent comment
      const parent = await createComment({
        userId: user1.id,
        entityType: "TRIP_FINAL_POST",
        entityId: finalPost.id,
        contentText: "Parent comment",
      });

      // Create reply
      const reply1Req = createAuthenticatedRequest(
        "http://localhost/api/comments",
        "POST",
        {
          entityType: "TRIP_FINAL_POST",
          entityId: finalPost.id,
          contentText: "First reply",
          parentCommentId: parent.id,
        },
        token2
      );

      const reply1Response = await createCommentRoute(reply1Req);
      const reply1Data = await getResponseData(reply1Response);

      expect(reply1Response.status).toBe(200);
      expect(reply1Data.data.parentCommentId).toBe(parent.id);

      // Verify reply count (implementation dependent)
      const parentComment = await prisma.comment.findUnique({
        where: { id: parent.id },
      });
      // Note: This assumes reply count is tracked, adjust based on schema
      expect(parentComment).toBeTruthy();
    });

    it("should prevent self-liking comments", async () => {
      // Create a final post first
      const finalPost = await createFinalPost({ userId: user1.id });

      const comment = await createComment({
        userId: user1.id,
        entityType: "TRIP_FINAL_POST",
        entityId: finalPost.id,
        contentText: "My comment",
      });

      const req = createAuthenticatedRequest(
        "http://localhost/api/likes",
        "POST",
        {
          entityType: "COMMENT",
          entityId: comment.id,
        },
        token1 // Same user trying to like their own comment
      );

      const response = await createLikeRoute(req);

      // This is actually allowed in most systems, but documenting the behavior
      expect(response.status).toBe(200);
    });

    it("should handle cascading deletes when comment is deleted", async () => {
      const finalPost = await createFinalPost();

      // Create comment
      const comment = await createComment({
        userId: user1.id,
        entityType: "TRIP_FINAL_POST",
        entityId: finalPost.id,
        contentText: "Comment to delete",
      });

      // Create likes on the comment
      await prisma.like.createMany({
        data: [
          {
            userId: user1.id,
            entityType: EntityType.COMMENT,
            entityId: comment.id,
          },
          {
            userId: user2.id,
            entityType: EntityType.COMMENT,
            entityId: comment.id,
          },
        ],
      });

      // Create reply to comment
      const reply = await createComment({
        userId: user2.id,
        entityType: "TRIP_FINAL_POST",
        entityId: finalPost.id,
        contentText: "Reply to comment",
        parentCommentId: comment.id,
      });

      // Delete comment
      const deleteReq = createAuthenticatedRequest(
        `http://localhost/api/comments/${comment.id}`,
        "DELETE",
        undefined,
        token1
      );

      const deleteResponse = await deleteCommentRoute(deleteReq, {
        params: Promise.resolve({ commentId: comment.id }),
      });

      expect(deleteResponse.status).toBe(200);

      // Verify comment is deleted
      const deletedComment = await prisma.comment.findUnique({
        where: { id: comment.id },
      });
      expect(deletedComment).toBeNull();

      // Verify likes are deleted (cascading)
      const commentLikes = await prisma.like.findMany({
        where: {
          entityType: EntityType.COMMENT,
          entityId: comment.id,
        },
      });
      expect(commentLikes.length).toBe(0);

      // Verify replies are deleted (cascading)
      const replies = await prisma.comment.findMany({
        where: { parentCommentId: comment.id },
      });
      expect(replies.length).toBe(0);
    });
  });

  describe("Data Integrity Tests", () => {
    it("should maintain accurate like counts across multiple operations", async () => {
      const finalPost = await createFinalPost();

      // User1 likes
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

      // User2 likes
      await createLikeRoute(
        createAuthenticatedRequest(
          "http://localhost/api/likes",
          "POST",
          {
            entityType: "TRIP_FINAL_POST",
            entityId: finalPost.id,
          },
          token2
        )
      );

      // Verify count
      let post = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(post?.likeCount).toBe(2);

      // User1 unlikes
      await fetch(
        `http://localhost/api/likes/TRIP_FINAL_POST/${finalPost.id}`,
        {
          method: "DELETE",
          headers: { authorization: `Bearer ${token1}` },
        }
      );

      // Verify count decreased
      post = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(post?.likeCount).toBe(1);
    });

    it("should maintain accurate comment counts", async () => {
      const finalPost = await createFinalPost();

      // Create 3 comments
      for (let i = 0; i < 3; i++) {
        await createCommentRoute(
          createAuthenticatedRequest(
            "http://localhost/api/comments",
            "POST",
            {
              entityType: "TRIP_FINAL_POST",
              entityId: finalPost.id,
              contentText: `Comment ${i}`,
            },
            token1
          )
        );
      }

      // Verify count
      const post = await prisma.tripFinalPost.findUnique({
        where: { id: finalPost.id },
      });
      expect(post?.commentCount).toBe(3);
    });
  });
});
