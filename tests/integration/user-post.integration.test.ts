import { beforeEach, describe, expect, it } from "vitest";
import { NextRequest } from "next/server";
import { randomUUID } from "crypto";
import { MediaType, UserSafetyAction } from "@prisma/client";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser, getAuthToken } from "../testUtils";
import { POST as createUserPost } from "../../src/app/api/user-posts/route";
import {
  DELETE as deleteUserPost,
  PATCH as updateUserPost,
} from "../../src/app/api/user-posts/[id]/route";
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

async function ownPhoto(userId: string, url: string) {
  await prisma.media.create({
    data: {
      url,
      publicId: `direct-${randomUUID()}`,
      type: MediaType.IMAGE,
      uploadedById: userId,
    },
  });
}

describe("Direct posts", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("saves an unpublished draft that stays off the home feed", async () => {
    const author = await createUser({ email: "draft-author@test.com", name: "Draft" });
    const photo = "https://cdn.example.com/draft-photo.jpg";
    await ownPhoto(author.id, photo);
    const token = await getAuthToken(author);

    const created = await createUserPost(
      authRequest("http://localhost/api/user-posts", "POST", token, {
        caption: "Draft caption only",
        media: [photo],
        locationName: "Quiet cove",
        latitude: 12.3,
        longitude: 45.6,
        isPublished: false,
      })
    );
    const body = await json(created);
    expect(created.status).toBe(200);
    expect(body.data.isPublished).toBe(false);
    expect(body.data.mapPins).toEqual([
      { lat: 12.3, lng: 45.6, name: "Quiet cove" },
    ]);

    const feed = await getFeedRoute(
      authRequest("http://localhost/api/feed/home", "GET", token)
    );
    const feedBody = await json(feed);
    const feedItem = feedBody.data.items.find(
      (item: { id: string }) => item.id === body.data.id
    );
    expect(feedItem).toBeUndefined();

    const published = await updateUserPost(
      authRequest(
        `http://localhost/api/user-posts/${body.data.id}`,
        "PATCH",
        token,
        {
          caption: "Draft caption only",
          media: [photo],
          locationName: "Quiet cove",
          latitude: 12.3,
          longitude: 45.6,
          isPublished: true,
        }
      )
    );
    const publishedBody = await json(published);
    expect(published.status).toBe(200);
    expect(publishedBody.data.isPublished).toBe(true);
  });

  it("publishes a caption, the author's photo, and a location", async () => {
    const author = await createUser({ email: "direct-author@test.com", name: "Author" });
    const photo = "https://cdn.example.com/direct-photo.jpg";
    await ownPhoto(author.id, photo);
    const token = await getAuthToken(author);

    const created = await createUserPost(
      authRequest("http://localhost/api/user-posts", "POST", token, {
        caption: "Evening light on the ridge",
        media: [photo],
        locationName: "Ridge road",
        latitude: 30.7,
        longitude: 79.1,
      })
    );
    const body = await json(created);
    expect(created.status).toBe(200);
    expect(body.data.postKind).toBe("direct");
    expect(body.data.curatedMedia).toEqual([photo]);
    expect(body.data.locationName).toBe("Ridge road");
    expect(body.data.tripId).toBeNull();
    expect(body.data.templateChoice).toBe("postcard");
    expect(body.data.threadPreview).toEqual([]);
    expect(body.data.mapPins).toEqual([
      { lat: 30.7, lng: 79.1, name: "Ridge road" },
    ]);

    const viewer = await createUser({ email: "direct-viewer@test.com", name: "Viewer" });
    const feed = await getFeedRoute(
      authRequest(
        "http://localhost/api/feed/home",
        "GET",
        await getAuthToken(viewer)
      )
    );
    const feedBody = await json(feed);
    const feedItem = feedBody.data.items.find(
      (item: { id: string }) => item.id === body.data.id
    );
    expect(feedItem).toBeTruthy();
    expect(feedItem.templateChoice).toBe("postcard");
    expect(feedItem.threadPreview).toEqual([]);
    expect(feedItem.mapPins?.[0]?.name).toBe("Ridge road");
    expect(feedItem.postKind).toBe("direct");

    const updated = await updateUserPost(
      authRequest(
        `http://localhost/api/user-posts/${body.data.id}`,
        "PATCH",
        token,
        {
          caption: "Evening light, revised",
          media: [photo],
          locationName: "Ridge road",
        }
      ),
      { params: Promise.resolve({ id: body.data.id }) }
    );
    expect((await json(updated)).data.summaryText).toBe("Evening light, revised");

    const removed = await deleteUserPost(
      authRequest(
        `http://localhost/api/user-posts/${body.data.id}`,
        "DELETE",
        token
      ),
      { params: Promise.resolve({ id: body.data.id }) }
    );
    expect(removed.status).toBe(200);
    expect(await prisma.userPost.count()).toBe(0);
  });

  it("rejects a photo the author did not upload", async () => {
    const author = await createUser({ email: "direct-gate@test.com", name: "Author" });
    const token = await getAuthToken(author);
    const response = await createUserPost(
      authRequest("http://localhost/api/user-posts", "POST", token, {
        caption: "Not my photo",
        media: ["https://cdn.example.com/someone-else.jpg"],
      })
    );
    expect(response.status).toBe(400);
    expect(await prisma.userPost.count()).toBe(0);
  });

  it("hides a direct post from someone the author blocked", async () => {
    const author = await createUser({ email: "direct-block-a@test.com", name: "Author" });
    const other = await createUser({ email: "direct-block-b@test.com", name: "Other" });
    const photo = "https://cdn.example.com/blocked-direct.jpg";
    await ownPhoto(author.id, photo);
    await prisma.userPost.create({
      data: {
        userId: author.id,
        caption: "Private to the block",
        media: [photo],
        isPublished: true,
        publishedAt: new Date(),
      },
    });
    await prisma.userSafetyRelation.create({
      data: {
        actorId: author.id,
        targetId: other.id,
        action: UserSafetyAction.BLOCK,
      },
    });

    const feed = await getFeedRoute(
      authRequest(
        "http://localhost/api/feed/home",
        "GET",
        await getAuthToken(other)
      )
    );
    const body = await json(feed);
    expect(body.data.items).toEqual([]);
  });
});
