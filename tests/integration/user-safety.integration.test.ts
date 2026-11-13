import { describe, it, expect, beforeEach } from "vitest";
import { GenerationStatus, MediaType, TripStatus, UserSafetyAction } from "@prisma/client";
import { randomUUID } from "crypto";
import { NextRequest } from "next/server";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser, createTrip, getAuthToken } from "../testUtils";
import { POST as followPost } from "../../src/app/api/follow/[userId]/route";
import { GET as getUser } from "../../src/app/api/users/[id]/route";
import { GET as searchUsers } from "../../src/app/api/users/route";
import { GET as getHomeFeed } from "../../src/app/api/feed/home/route";
import { GET as getDiscoverTrips } from "../../src/app/api/discover/trips/route";
import { GET as getPost } from "../../src/app/api/posts/[entityType]/[entityId]/route";
import { GET as getTrip } from "../../src/app/api/trips/[id]/route";
import { canViewEntity } from "../../src/lib/auth/permissions";
import {
  addGroupParticipant,
  createConversation,
  listConversationMedia,
  sendMessage,
} from "../../src/lib/services/chat";
import {
  CANNOT_ADD,
  CANNOT_MESSAGE,
  isProfileUnavailable,
  listSafetyActions,
  setSafetyAction,
  clearSafetyAction,
} from "../../src/lib/services/userSafety";
import { AuthorizationError } from "../../src/lib/errors";
import { TripInvitationService } from "../../src/lib/tripInvitation";

describe("Restrict and Block", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  it("stops direct messages both ways and keeps the existing thread", async () => {
    const alice = await createUser({ email: "alice-restrict@test.com" });
    const bob = await createUser({ email: "bob-restrict@test.com" });
    const conv = await createConversation(
      { type: "DM", participantIds: [bob.id] },
      alice.id
    );
    await sendMessage(conv.id, alice.id, { content: "hello" });

    await setSafetyAction(alice.id, bob.id, UserSafetyAction.RESTRICT);

    await expect(
      sendMessage(conv.id, bob.id, { content: "reply" })
    ).rejects.toThrow(CANNOT_MESSAGE);
    await expect(
      sendMessage(conv.id, alice.id, { content: "again" })
    ).rejects.toThrow(CANNOT_MESSAGE);

    const stored = await prisma.chatMessage.findMany({
      where: { conversationId: conv.id },
    });
    expect(stored).toHaveLength(1);

    const carol = await createUser({ email: "carol-restrict@test.com" });
    await setSafetyAction(alice.id, carol.id, UserSafetyAction.BLOCK);
    await expect(
      createConversation({ type: "DM", participantIds: [carol.id] }, alice.id)
    ).rejects.toThrow(AuthorizationError);

    const group = await createConversation(
      { type: "GROUP", name: "Still open", participantIds: [bob.id] },
      alice.id
    );
    await expect(
      sendMessage(group.id, alice.id, { content: "group still works" })
    ).resolves.toMatchObject({ content: "group still works" });
  });

  it("removes their follow and hides the profile", async () => {
    const alice = await createUser({ email: "alice-block@test.com" });
    const bob = await createUser({ email: "bob-block@test.com" });
    await prisma.follow.create({
      data: { followerId: bob.id, followeeId: alice.id },
    });
    await prisma.followRequest.create({
      data: { followerId: bob.id, followeeId: alice.id, status: "PENDING" },
    });

    await setSafetyAction(alice.id, bob.id, UserSafetyAction.BLOCK);

    expect(
      await prisma.follow.count({
        where: { followerId: bob.id, followeeId: alice.id },
      })
    ).toBe(0);
    expect(await isProfileUnavailable(alice.id, bob.id)).toBe(true);
    expect(await isProfileUnavailable(bob.id, alice.id)).toBe(false);

    const listed = await listSafetyActions(alice.id, UserSafetyAction.BLOCK);
    expect(listed.people.map((person) => person.id)).toEqual([bob.id]);

    await expect(
      setSafetyAction(alice.id, bob.id, UserSafetyAction.RESTRICT)
    ).rejects.toThrow(/Unblock/);
    await clearSafetyAction(alice.id, bob.id);
    expect(await isProfileUnavailable(alice.id, bob.id)).toBe(false);
  });

  it("refuses a follow from someone who was blocked", async () => {
    const alice = await createUser({ email: "alice-follow@test.com" });
    const bob = await createUser({ email: "bob-follow@test.com" });
    await setSafetyAction(alice.id, bob.id, UserSafetyAction.BLOCK);
    const token = await getAuthToken(bob);
    const followResponse = await followPost(
      new NextRequest(`http://localhost/api/follow/${alice.id}`, {
        method: "POST",
        headers: { authorization: `Bearer ${token}` },
      }),
      { params: Promise.resolve({ userId: alice.id }) }
    );
    expect(followResponse.status).toBe(403);

    const profileResponse = await getUser(
      new NextRequest(`http://localhost/api/users/${alice.id}`, {
        headers: { authorization: `Bearer ${token}` },
      }),
      { params: Promise.resolve({ id: alice.id }) }
    );
    const profileBody = await profileResponse.json();
    expect(profileResponse.status).toBe(200);
    expect(profileBody.data.viewerIsBlocked).toBe(true);
    expect(profileBody.data.blockedByViewer ?? false).toBe(false);
    expect(profileBody.data.email).toBe("");
    expect(profileBody.data.avatarUrl ?? null).toBeNull();
    expect(profileBody.data.bio ?? null).toBeNull();
    expect(profileBody.data.username).toBe(alice.username);
  });

  it("keeps a blocked person's posts out of Home and Discover", async () => {
    const alice = await createUser({
      email: "alice-feed@test.com",
      username: "alicefeed",
      name: "Alice Feed",
    });
    const bob = await createUser({
      email: "bob-feed@test.com",
      username: "bobfeed",
      name: "Bob Feed",
    });
    const trip = await createTrip({
      userId: bob.id,
      title: "Bob public trip",
      status: TripStatus.ENDED,
    });
    const post = await prisma.tripFinalPost.create({
      data: {
        tripId: trip.id,
        userId: bob.id,
        summaryText: "Bob wrote a public recap long enough to publish here.",
        curatedMedia: ["https://cdn.example.com/bob.jpg"],
        isPublished: true,
        publishedAt: new Date(),
        generationStatus: GenerationStatus.PUBLISHED,
      },
    });

    await prisma.user.update({
      where: { id: alice.id },
      data: {
        avatarUrl: "https://cdn.example.com/alice.png",
        bio: "Alice bio",
      },
    });
    await prisma.user.update({
      where: { id: bob.id },
      data: {
        avatarUrl: "https://cdn.example.com/bob.png",
        bio: "Bob bio",
      },
    });
    await setSafetyAction(alice.id, bob.id, UserSafetyAction.BLOCK);
    const token = await getAuthToken(alice);
    const auth = { authorization: `Bearer ${token}` };

    const feed = await getHomeFeed(
      new NextRequest("http://localhost/api/feed/home", { headers: auth })
    );
    const feedBody = await feed.json();
    expect(feed.status).toBe(200);
    expect(
      feedBody.data.items.map((item: { id: string }) => item.id)
    ).not.toContain(post.id);

    const discover = await getDiscoverTrips(
      new NextRequest(
        "http://localhost/api/discover/trips?q=Bob%20public",
        { headers: auth }
      )
    );
    const discoverBody = await discover.json();
    expect(discover.status).toBe(200);
    expect(
      discoverBody.data.items.map((item: { id: string }) => item.id)
    ).not.toContain(trip.id);

    const search = await searchUsers(
      new NextRequest("http://localhost/api/users?search=bobfeed", {
        headers: auth,
      })
    );
    const searchBody = await search.json();
    expect(search.status).toBe(200);
    const bobHit = searchBody.data.items.find(
      (item: { id: string }) => item.id === bob.id
    );
    expect(bobHit).toBeTruthy();
    expect(bobHit.avatarUrl ?? null).toBeNull();
    expect(bobHit.bio ?? null).toBeNull();
    expect(bobHit.username).toBe("bobfeed");

    const profile = await getUser(
      new NextRequest(`http://localhost/api/users/${bob.id}`, {
        headers: auth,
      }),
      { params: Promise.resolve({ id: bob.id }) }
    );
    const profileBody = await profile.json();
    expect(profile.status).toBe(200);
    expect(profileBody.data.blockedByViewer).toBe(true);
    expect(profileBody.data.viewerIsBlocked ?? false).toBe(false);
    expect(profileBody.data.email).toBe("");
    expect(profileBody.data.username).toBe("bobfeed");
    expect(profileBody.data.name).toBe("Bob Feed");
    expect(profileBody.data.avatarUrl ?? null).toBeNull();
    expect(profileBody.data.bio ?? null).toBeNull();

    const bobToken = await getAuthToken(bob);
    const aliceProfile = await getUser(
      new NextRequest(`http://localhost/api/users/${alice.id}`, {
        headers: { authorization: `Bearer ${bobToken}` },
      }),
      { params: Promise.resolve({ id: alice.id }) }
    );
    const aliceProfileBody = await aliceProfile.json();
    expect(aliceProfile.status).toBe(200);
    expect(aliceProfileBody.data.viewerIsBlocked).toBe(true);
    expect(aliceProfileBody.data.blockedByViewer ?? false).toBe(false);
    expect(aliceProfileBody.data.email).toBe("");
    expect(aliceProfileBody.data.username).toBe("alicefeed");
    expect(aliceProfileBody.data.avatarUrl ?? null).toBeNull();
    expect(aliceProfileBody.data.bio ?? null).toBeNull();

    const bobFeed = await getHomeFeed(
      new NextRequest("http://localhost/api/feed/home", {
        headers: { authorization: `Bearer ${bobToken}` },
      })
    );
    const bobFeedBody = await bobFeed.json();
    expect(
      bobFeedBody.data.items.map((item: { userId: string }) => item.userId)
    ).not.toContain(alice.id);

    const opened = await getPost(
      new NextRequest(
        `http://localhost/api/posts/TRIP_FINAL_POST/${post.id}`,
        { headers: auth }
      ),
      {
        params: Promise.resolve({
          entityType: "TRIP_FINAL_POST",
          entityId: post.id,
        }),
      }
    );
    const tripView = await getTrip(
      new NextRequest(`http://localhost/api/trips/${trip.id}`, {
        headers: auth,
      }),
      { params: Promise.resolve({ id: trip.id }) }
    );
    expect(tripView.status).toBe(404);

    expect(opened.status).toBe(403);
    expect(await canViewEntity(alice.id, "TRIP_FINAL_POST", post.id)).toBe(
      false
    );

    await clearSafetyAction(alice.id, bob.id);
    const restored = await getHomeFeed(
      new NextRequest("http://localhost/api/feed/home", { headers: auth })
    );
    const restoredBody = await restored.json();
    expect(
      restoredBody.data.items.map((item: { id: string }) => item.id)
    ).toContain(post.id);
    const restoredDiscover = await getDiscoverTrips(
      new NextRequest(
        "http://localhost/api/discover/trips?q=Bob%20public",
        { headers: auth }
      )
    );
    const restoredDiscoverBody = await restoredDiscover.json();
    expect(
      restoredDiscoverBody.data.items.map((item: { id: string }) => item.id)
    ).toContain(trip.id);
    expect(await canViewEntity(alice.id, "TRIP_FINAL_POST", post.id)).toBe(
      true
    );

    const restoredProfile = await getUser(
      new NextRequest(`http://localhost/api/users/${bob.id}`, {
        headers: auth,
      }),
      { params: Promise.resolve({ id: bob.id }) }
    );
    const restoredProfileBody = await restoredProfile.json();
    expect(restoredProfile.status).toBe(200);
    expect(restoredProfileBody.data.blockedByViewer ?? false).toBe(false);
    expect(restoredProfileBody.data.email).toBe(bob.email);
  });

  it("lets a third person put both people on their trip and group", async () => {
    const alice = await createUser({ email: "alice-trip@test.com" });
    const bob = await createUser({ email: "bob-trip@test.com" });
    const cara = await createUser({ email: "cara-trip@test.com" });
    await setSafetyAction(alice.id, bob.id, UserSafetyAction.BLOCK);

    const aliceTrip = await createTrip({
      userId: alice.id,
      title: "Alice trip",
    });
    await expect(
      TripInvitationService.sendInvitation(aliceTrip.id, alice.id, bob.id)
    ).rejects.toThrow(CANNOT_ADD);

    const caraTrip = await createTrip({ userId: cara.id, title: "Cara trip" });
    await expect(
      TripInvitationService.sendInvitation(caraTrip.id, cara.id, alice.id)
    ).resolves.toMatchObject({ status: "PENDING" });
    await expect(
      TripInvitationService.sendInvitation(caraTrip.id, cara.id, bob.id)
    ).resolves.toMatchObject({ status: "PENDING" });

    const caraGroup = await createConversation(
      { type: "GROUP", name: "Cara group", participantIds: [alice.id] },
      cara.id
    );
    await expect(
      addGroupParticipant(caraGroup.id, cara.id, bob.id)
    ).resolves.toBeTruthy();

    const aliceGroup = await createConversation(
      { type: "GROUP", name: "Alice group", participantIds: [cara.id] },
      alice.id
    );
    await expect(
      addGroupParticipant(aliceGroup.id, alice.id, bob.id)
    ).rejects.toThrow(CANNOT_ADD);
  });

  it("pages conversation media newest first", async () => {
    const alice = await createUser({ email: "alice-media@test.com" });
    const bob = await createUser({ email: "bob-media@test.com" });
    const conv = await createConversation(
      { type: "DM", participantIds: [bob.id] },
      alice.id
    );
    const first = await prisma.media.create({
      data: {
        url: "https://cdn.example.com/one.jpg",
        publicId: `one-${randomUUID()}`,
        type: MediaType.IMAGE,
        uploadedById: alice.id,
      },
    });
    const second = await prisma.media.create({
      data: {
        url: "https://cdn.example.com/two.jpg",
        publicId: `two-${randomUUID()}`,
        type: MediaType.IMAGE,
        uploadedById: alice.id,
        createdAt: new Date(Date.now() + 1000),
      },
    });
    await sendMessage(conv.id, alice.id, {
      content: "one",
      attachmentMediaIds: [first.id],
    });
    await sendMessage(conv.id, alice.id, {
      content: "two",
      attachmentMediaIds: [second.id],
    });

    const page = await listConversationMedia(conv.id, bob.id, { limit: 1 });
    expect(page.items).toHaveLength(1);
    expect(page.hasMore).toBe(true);
    expect(page.items[0].id).toBe(second.id);
    const next = await listConversationMedia(conv.id, bob.id, {
      limit: 1,
      cursor: page.nextCursor!,
    });
    expect(next.items.map((item) => item.id)).toEqual([first.id]);
    expect(next.hasMore).toBe(false);
  });
});
