import { describe, it, expect, beforeEach } from "vitest";
import { NextRequest } from "next/server";
import { EntityType, NotificationType, TripStatus } from "@prisma/client";
import { prisma } from "../../src/lib/prisma";
import {
  cleanDb,
  createComment as createCommentRecord,
  createFinalPost,
  createThreadEntry,
  createTrip,
  createUser,
  getAuthToken,
} from "../testUtils";
import { createLike } from "../../src/lib/services/like";
import { createComment as createCommentService } from "../../src/lib/services/comment";
import { GET as getNotificationsRoute } from "../../src/app/api/users/me/notifications/route";
import { PUT as markNotificationReadRoute } from "../../src/app/api/users/me/notifications/[id]/read/route";

function createAuthenticatedRequest(
  url: string,
  method: string = "GET",
  body?: unknown,
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

async function waitFor(
  predicate: () => Promise<boolean>,
  timeoutMs = 2000,
  intervalMs = 50
) {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    if (await predicate()) return;
    await new Promise((resolve) => setTimeout(resolve, intervalMs));
  }
  throw new Error("Timed out waiting for async side effect");
}

describe("Notifications improvements", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("does not create duplicate LIKE notifications for idempotent likes", async () => {
    const owner = await createUser({ email: "owner-like@test.com" });
    const actor = await createUser({ email: "actor-like@test.com" });
    const post = await createFinalPost({ userId: owner.id, isPublished: true });

    await createLike(actor.id, EntityType.TRIP_FINAL_POST, post.id);
    await createLike(actor.id, EntityType.TRIP_FINAL_POST, post.id);

    await waitFor(async () => {
      const count = await prisma.notification.count({
        where: {
          type: NotificationType.LIKE,
          actorId: actor.id,
          recipientId: owner.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: post.id,
        },
      });
      return count === 1;
    });

    const notifCount = await prisma.notification.count({
      where: {
        type: NotificationType.LIKE,
        actorId: actor.id,
        recipientId: owner.id,
        entityType: EntityType.TRIP_FINAL_POST,
        entityId: post.id,
      },
    });
    expect(notifCount).toBe(1);
  });

  it("stores tripId/threadEntryId metadata for thread-entry comment and comment-like notifications", async () => {
    const owner = await createUser({ email: "owner-thread@test.com" });
    const commenter = await createUser({ email: "commenter-thread@test.com" });
    const liker = await createUser({ email: "liker-thread@test.com" });

    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    const entry = await createThreadEntry({ tripId: trip.id, userId: owner.id });

    const createdComment = await createCommentService(
      commenter.id,
      EntityType.TRIP_THREAD_ENTRY,
      entry.id,
      "Nice entry!"
    );

    await waitFor(async () => {
      const notif = await prisma.notification.findFirst({
        where: {
          type: NotificationType.COMMENT,
          actorId: commenter.id,
          recipientId: owner.id,
          entityType: EntityType.TRIP_THREAD_ENTRY,
          entityId: entry.id,
        },
      });
      return !!notif;
    });

    const commentNotif = await prisma.notification.findFirstOrThrow({
      where: {
        type: NotificationType.COMMENT,
        actorId: commenter.id,
        recipientId: owner.id,
        entityType: EntityType.TRIP_THREAD_ENTRY,
        entityId: entry.id,
      },
    });
    const commentMeta = commentNotif.metadata as Record<string, unknown>;
    expect(commentMeta.tripId).toBe(trip.id);
    expect(commentMeta.threadEntryId).toBe(entry.id);

    await createLike(liker.id, EntityType.COMMENT, createdComment.id);

    await waitFor(async () => {
      const notif = await prisma.notification.findFirst({
        where: {
          type: NotificationType.COMMENT_LIKE,
          actorId: liker.id,
          recipientId: commenter.id,
          entityType: EntityType.COMMENT,
          entityId: createdComment.id,
        },
      });
      return !!notif;
    });

    const likeNotif = await prisma.notification.findFirstOrThrow({
      where: {
        type: NotificationType.COMMENT_LIKE,
        actorId: liker.id,
        recipientId: commenter.id,
        entityType: EntityType.COMMENT,
        entityId: createdComment.id,
      },
    });
    const likeMeta = likeNotif.metadata as Record<string, unknown>;
    expect(likeMeta.postEntityType).toBe("TRIP_THREAD_ENTRY");
    expect(likeMeta.postEntityId).toBe(entry.id);
    expect(likeMeta.tripId).toBe(trip.id);
    expect(likeMeta.threadEntryId).toBe(entry.id);
  });

  it("does not send TAG mention notifications when mentioned user cannot view private content", async () => {
    const owner = await createUser({ email: "owner-private@test.com" });
    await prisma.user.update({
      where: { id: owner.id },
      data: { isPrivate: true },
    });

    const commenter = await createUser({ email: "commenter-private@test.com" });
    const mentioned = await createUser({
      email: "mentioned-private@test.com",
      username: "mentioneduser",
    });

    const trip = await createTrip({ userId: owner.id, status: TripStatus.ONGOING });
    const entry = await createThreadEntry({ tripId: trip.id, userId: owner.id });

    await createCommentService(
      commenter.id,
      EntityType.TRIP_THREAD_ENTRY,
      entry.id,
      "Hello @mentioneduser"
    );

    await new Promise((resolve) => setTimeout(resolve, 150));

    const blockedCount = await prisma.notification.count({
      where: {
        type: NotificationType.TAG,
        recipientId: mentioned.id,
      },
    });
    expect(blockedCount).toBe(0);

    await prisma.follow.create({
      data: {
        followerId: mentioned.id,
        followeeId: owner.id,
      },
    });

    await createCommentService(
      commenter.id,
      EntityType.TRIP_THREAD_ENTRY,
      entry.id,
      "Second ping @mentioneduser"
    );

    await waitFor(async () => {
      const count = await prisma.notification.count({
        where: {
          type: NotificationType.TAG,
          recipientId: mentioned.id,
        },
      });
      return count === 1;
    });

    const allowedTag = await prisma.notification.findFirstOrThrow({
      where: {
        type: NotificationType.TAG,
        recipientId: mentioned.id,
      },
    });
    const meta = allowedTag.metadata as Record<string, unknown>;
    expect(meta.postEntityType).toBe("TRIP_THREAD_ENTRY");
    expect(meta.tripId).toBe(trip.id);
    expect(meta.threadEntryId).toBe(entry.id);
  });

  it("supports merged notification pagination and deep-link payload consistency", async () => {
    const recipient = await createUser({ email: "recipient-merged@test.com" });
    const actorA = await createUser({ email: "actorA-merged@test.com" });
    const actorB = await createUser({ email: "actorB-merged@test.com" });
    const follower = await createUser({ email: "follower-merged@test.com" });

    const trip = await createTrip({
      userId: recipient.id,
      status: TripStatus.ONGOING,
    });
    const entry = await createThreadEntry({ tripId: trip.id, userId: recipient.id });
    const comment = await createCommentRecord({
      userId: actorA.id,
      entityType: "TRIP_THREAD_ENTRY",
      entityId: entry.id,
      contentText: "payload comment",
    });

    await prisma.followRequest.create({
      data: {
        followerId: follower.id,
        followeeId: recipient.id,
        status: "PENDING",
        createdAt: new Date("2026-01-10T10:00:00.000Z"),
      },
    });

    await prisma.notification.create({
      data: {
        type: NotificationType.COMMENT,
        actorId: actorA.id,
        recipientId: recipient.id,
        entityType: EntityType.TRIP_THREAD_ENTRY,
        entityId: entry.id,
        createdAt: new Date("2026-01-10T09:00:00.000Z"),
        metadata: {
          tripId: trip.id,
          threadEntryId: entry.id,
          commentId: comment.id,
          postEntityType: "TRIP_THREAD_ENTRY",
          postEntityId: entry.id,
        },
      },
    });

    await prisma.notification.create({
      data: {
        type: NotificationType.LIKE,
        actorId: actorB.id,
        recipientId: recipient.id,
        entityType: EntityType.TRIP_FINAL_POST,
        entityId: "final-post-id-123",
        createdAt: new Date("2026-01-10T08:00:00.000Z"),
      },
    });

    const token = await getAuthToken(recipient);
    const reqPage1 = createAuthenticatedRequest(
      "http://localhost/api/users/me/notifications?limit=2",
      "GET",
      undefined,
      token
    );
    const page1Response = await getNotificationsRoute(reqPage1);
    const page1Data = await getResponseData(page1Response);

    expect(page1Response.status).toBe(200);
    expect(page1Data.success).toBe(true);
    expect(page1Data.data.items.length).toBe(2);
    expect(page1Data.data.hasMore).toBe(true);

    const commentItem = page1Data.data.items.find(
      (item: Record<string, unknown>) => item.type === "COMMENT"
    ) as Record<string, unknown> | undefined;
    expect(commentItem).toBeTruthy();
    expect(commentItem?.tripId).toBe(trip.id);
    expect(commentItem?.threadEntryId).toBe(entry.id);
    expect(commentItem?.postEntityType).toBe("TRIP_THREAD_ENTRY");
    expect(commentItem?.postEntityId).toBe(entry.id);

    const cursor = page1Data.data.nextCursor as string;
    expect(cursor).toBeTruthy();
    const reqPage2 = createAuthenticatedRequest(
      `http://localhost/api/users/me/notifications?limit=2&cursor=${encodeURIComponent(cursor)}`,
      "GET",
      undefined,
      token
    );
    const page2Response = await getNotificationsRoute(reqPage2);
    const page2Data = await getResponseData(page2Response);

    expect(page2Response.status).toBe(200);
    expect(page2Data.success).toBe(true);
    expect(page2Data.data.items.length).toBeGreaterThan(0);
  });

  it("keeps pagination stable when notifications share the same createdAt timestamp", async () => {
    const recipient = await createUser({ email: "recipient-tie@test.com" });
    const actorA = await createUser({ email: "actorA-tie@test.com" });
    const actorB = await createUser({ email: "actorB-tie@test.com" });

    const sharedCreatedAt = new Date("2026-01-15T10:00:00.000Z");
    await prisma.notification.createMany({
      data: [
        {
          type: NotificationType.LIKE,
          actorId: actorA.id,
          recipientId: recipient.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: "tie-post-a",
          createdAt: sharedCreatedAt,
        },
        {
          type: NotificationType.COMMENT,
          actorId: actorB.id,
          recipientId: recipient.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: "tie-post-b",
          createdAt: sharedCreatedAt,
        },
      ],
    });

    const token = await getAuthToken(recipient);
    const page1Req = createAuthenticatedRequest(
      "http://localhost/api/users/me/notifications?limit=1",
      "GET",
      undefined,
      token
    );
    const page1Res = await getNotificationsRoute(page1Req);
    const page1 = await getResponseData(page1Res);
    expect(page1Res.status).toBe(200);
    expect(page1.data.items.length).toBe(1);
    expect(page1.data.nextCursor).toBeTruthy();

    const page2Req = createAuthenticatedRequest(
      `http://localhost/api/users/me/notifications?limit=2&cursor=${encodeURIComponent(page1.data.nextCursor as string)}`,
      "GET",
      undefined,
      token
    );
    const page2Res = await getNotificationsRoute(page2Req);
    const page2 = await getResponseData(page2Res);
    expect(page2Res.status).toBe(200);
    expect(page2.data.items.length).toBeGreaterThanOrEqual(1);

    const allIds = [
      ...(page1.data.items as Array<{ id: string }>).map((i) => i.id),
      ...(page2.data.items as Array<{ id: string }>).map((i) => i.id),
    ];
    expect(new Set(allIds).size).toBe(allIds.length);
    expect(allIds.length).toBe(2);
  });

  it("treats single-notification read as idempotent", async () => {
    const recipient = await createUser({ email: "recipient-read@test.com" });
    const actor = await createUser({ email: "actor-read@test.com" });
    const post = await createFinalPost({ userId: recipient.id, isPublished: true });
    await createLike(actor.id, EntityType.TRIP_FINAL_POST, post.id);

    await waitFor(async () => {
      const count = await prisma.notification.count({
        where: {
          type: NotificationType.LIKE,
          recipientId: recipient.id,
          actorId: actor.id,
          entityType: EntityType.TRIP_FINAL_POST,
          entityId: post.id,
        },
      });
      return count === 1;
    });

    const notif = await prisma.notification.findFirstOrThrow({
      where: {
        type: NotificationType.LIKE,
        recipientId: recipient.id,
        actorId: actor.id,
      },
      select: { id: true },
    });

    const token = await getAuthToken(recipient);
    const firstReadReq = createAuthenticatedRequest(
      `http://localhost/api/users/me/notifications/${notif.id}/read`,
      "PUT",
      undefined,
      token
    );
    const firstReadRes = await markNotificationReadRoute(firstReadReq, {
      params: Promise.resolve({ id: notif.id }),
    });
    const firstReadData = await getResponseData(firstReadRes);
    expect(firstReadRes.status).toBe(200);
    expect(firstReadData.success).toBe(true);
    expect(firstReadData.data.marked).toBe(true);

    const secondReadReq = createAuthenticatedRequest(
      `http://localhost/api/users/me/notifications/${notif.id}/read`,
      "PUT",
      undefined,
      token
    );
    const secondReadRes = await markNotificationReadRoute(secondReadReq, {
      params: Promise.resolve({ id: notif.id }),
    });
    const secondReadData = await getResponseData(secondReadRes);
    expect(secondReadRes.status).toBe(200);
    expect(secondReadData.success).toBe(true);
    expect(secondReadData.data.alreadyRead).toBe(true);
  });
});

