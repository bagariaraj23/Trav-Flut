import { describe, it, expect, beforeEach } from "vitest";
import { MediaType, UserSafetyAction } from "@prisma/client";
import { randomUUID } from "crypto";
import { NextRequest } from "next/server";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser, createTrip, getAuthToken } from "../testUtils";
import { POST as followPost } from "../../src/app/api/follow/[userId]/route";
import { GET as getUser } from "../../src/app/api/users/[id]/route";
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
    expect(profileResponse.status).toBe(404);
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
