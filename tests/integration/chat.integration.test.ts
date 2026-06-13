import { describe, it, expect, beforeEach } from "vitest";
import { prisma } from "../../src/lib/prisma";
import { cleanDb, createUser } from "../testUtils";
import {
  createConversation,
  sendMessage,
  editMessage,
  deleteMessage,
  updateGroupDetails,
  addGroupParticipant,
  removeGroupParticipant,
  promoteToAdmin,
} from "../../src/lib/services/chat";
import { ValidationError, AuthorizationError } from "../../src/lib/errors";

describe("Chat Service Integration Tests", () => {
  beforeEach(async () => {
    await cleanDb();
  });

  describe("createConversation", () => {
    it("successfully creates a 1:1 conversation", async () => {
      const u1 = await createUser({ email: "user1@test.com" });
      const u2 = await createUser({ email: "user2@test.com" });

      const conv = await createConversation(
        {
          type: "DM",
          participantIds: [u2.id],
        },
        u1.id
      );

      expect(conv.type).toBe("DM");
      expect(conv.participants).toHaveLength(2);
    });

    it("successfully creates a group conversation", async () => {
      const u1 = await createUser({ email: "creator@test.com" });
      const u2 = await createUser({ email: "member1@test.com" });

      const conv = await createConversation(
        {
          type: "GROUP",
          name: "Test Group",
          participantIds: [u2.id],
        },
        u1.id
      );

      expect(conv.type).toBe("GROUP");
      expect(conv.name).toBe("Test Group");
      expect(conv.participants).toHaveLength(2);
    });

    it("fails to create a group conversation with more than 16 total participants", async () => {
      const creator = await createUser({ email: "creator-limit@test.com" });
      const participantIds: string[] = [];

      // Add 16 participants (which means 17 total members including the creator)
      for (let i = 0; i < 16; i++) {
        const u = await createUser({ email: `participant-${i}@test.com` });
        participantIds.push(u.id);
      }

      await expect(
        createConversation(
          {
            type: "GROUP",
            name: "Too Big Group",
            participantIds,
          },
          creator.id
        )
      ).rejects.toThrow(ValidationError);
    });
  });

  describe("editMessage", () => {
    it("allows editing a message within 15 minutes of creation", async () => {
      const creator = await createUser({ email: "edit-ok-c@test.com" });
      const other = await createUser({ email: "edit-ok-o@test.com" });
      const conv = await createConversation(
        {
          type: "DM",
          participantIds: [other.id],
        },
        creator.id
      );

      const msg = await sendMessage(conv.id, creator.id, { content: "Original content" });

      const edited = await editMessage(conv.id, msg.id, creator.id, "Edited content");
      expect(edited.content).toBe("Edited content");
    });

    it("fails to edit a message if new content is longer than 512 characters", async () => {
      const creator = await createUser({ email: "edit-len-c@test.com" });
      const other = await createUser({ email: "edit-len-o@test.com" });
      const conv = await createConversation(
        {
          type: "DM",
          participantIds: [other.id],
        },
        creator.id
      );

      const msg = await sendMessage(conv.id, creator.id, { content: "Original content" });
      const tooLong = "a".repeat(513);

      await expect(
        editMessage(conv.id, msg.id, creator.id, tooLong)
      ).rejects.toThrow(ValidationError);
    });

    it("fails to edit a message after 15 minutes", async () => {
      const creator = await createUser({ email: "edit-late-c@test.com" });
      const other = await createUser({ email: "edit-late-o@test.com" });
      const conv = await createConversation(
        {
          type: "DM",
          participantIds: [other.id],
        },
        creator.id
      );

      const msg = await sendMessage(conv.id, creator.id, { content: "Original content" });

      // Mock message creation date to be 16 minutes in the past
      await prisma.chatMessage.update({
        where: { id: msg.id },
        data: { createdAt: new Date(Date.now() - 16 * 60 * 1000) },
      });

      await expect(
        editMessage(conv.id, msg.id, creator.id, "Late edit content")
      ).rejects.toThrow(ValidationError);
    });
  });

  describe("deleteMessage", () => {
    it("allows deleting a message within 15 minutes (clears database string for privacy)", async () => {
      const creator = await createUser({ email: "del-ok-c@test.com" });
      const other = await createUser({ email: "del-ok-o@test.com" });
      const conv = await createConversation(
        {
          type: "DM",
          participantIds: [other.id],
        },
        creator.id
      );

      const msg = await sendMessage(conv.id, creator.id, { content: "Sensitive content" });

      await deleteMessage(conv.id, msg.id, creator.id);

      const dbMsg = await prisma.chatMessage.findUnique({
        where: { id: msg.id },
      });

      expect(dbMsg).not.toBeNull();
      expect(dbMsg!.content).toBe(""); // String is physically scrubbed from DB
      expect(dbMsg!.deletedAt).not.toBeNull();
    });

    it("fails to delete a message after 15 minutes", async () => {
      const creator = await createUser({ email: "del-late-c@test.com" });
      const other = await createUser({ email: "del-late-o@test.com" });
      const conv = await createConversation(
        {
          type: "DM",
          participantIds: [other.id],
        },
        creator.id
      );

      const msg = await sendMessage(conv.id, creator.id, { content: "Sensitive content" });

      // Mock message creation date to be 16 minutes in the past
      await prisma.chatMessage.update({
        where: { id: msg.id },
        data: { createdAt: new Date(Date.now() - 16 * 60 * 1000) },
      });

      await expect(
        deleteMessage(conv.id, msg.id, creator.id)
      ).rejects.toThrow(ValidationError);
    });
  });

  describe("updateGroupDetails", () => {
    it("allows group admin to update name and avatarUrl", async () => {
      const creator = await createUser({ email: "admin-g@test.com" });
      const member = await createUser({ email: "member-g@test.com" });
      const conv = await createConversation(
        {
          type: "GROUP",
          name: "Old Group Name",
          participantIds: [member.id],
        },
        creator.id
      );

      // Update name and avatar
      const updated = await updateGroupDetails(conv.id, creator.id, {
        name: "New Group Name",
        avatarUrl: "https://example.com/avatar.png",
      });

      expect(updated.name).toBe("New Group Name");
      expect(updated.avatarUrl).toBe("https://example.com/avatar.png");
    });

    it("fails to update if user is not group admin", async () => {
      const creator = await createUser({ email: "admin-g2@test.com" });
      const member = await createUser({ email: "member-g2@test.com" });
      const conv = await createConversation(
        {
          type: "GROUP",
          name: "Old Group Name",
          participantIds: [member.id],
        },
        creator.id
      );

      await expect(
        updateGroupDetails(conv.id, member.id, {
          name: "New Group Name",
        })
      ).rejects.toThrow(AuthorizationError);
    });
  });

  describe("Group participant actions", () => {
    it("allows admin to add/remove members and promote to admin", async () => {
      const creator = await createUser({ email: "admin-acts@test.com" });
      const member1 = await createUser({ email: "m1-acts@test.com" });
      const member2 = await createUser({ email: "m2-acts@test.com" });

      // Create group with creator and member1
      let conv = await createConversation(
        {
          type: "GROUP",
          name: "Manageable Group",
          participantIds: [member1.id],
        },
        creator.id
      );

      // 1. Add member2
      conv = await addGroupParticipant(conv.id, creator.id, member2.id);
      expect(conv.participants).toHaveLength(3);
      expect(conv.participants.map((p) => p.userId)).toContain(member2.id);

      // 2. Promote member1 to ADMIN
      conv = await promoteToAdmin(conv.id, creator.id, member1.id);
      const m1Role = conv.participants.find((p) => p.userId === member1.id)?.role;
      expect(m1Role).toBe("ADMIN");

      // 3. Remove member2
      conv = await removeGroupParticipant(conv.id, creator.id, member2.id);
      expect(conv.participants).toHaveLength(2);
      expect(conv.participants.map((p) => p.userId)).not.toContain(member2.id);
    });

    it("fails group management actions if initiator is not an admin", async () => {
      const creator = await createUser({ email: "creator-acts-err@test.com" });
      const member = await createUser({ email: "member-acts-err@test.com" });
      const target = await createUser({ email: "target-acts-err@test.com" });

      const conv = await createConversation(
        {
          type: "GROUP",
          name: "Secure Group",
          participantIds: [member.id],
        },
        creator.id
      );

      await expect(
        addGroupParticipant(conv.id, member.id, target.id)
      ).rejects.toThrow(AuthorizationError);
    });
  });
});
