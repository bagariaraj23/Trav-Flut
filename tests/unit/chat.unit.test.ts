import { describe, expect, it } from "vitest";
import { z } from "zod";

// We replicate and test the exact validation rules used by the Chat API endpoints and Services
const chatMessageSchema = z.string().min(1).max(512);
const groupNameSchema = z.string().min(1).max(100);
const avatarUrlSchema = z.string().url().nullable();

// Message edit/delete timeframe check logic
function isWithinTimeframe(createdAt: Date, timeframeMs: number): boolean {
  return Date.now() - createdAt.getTime() <= timeframeMs;
}

describe("Chat Validation Rules", () => {
  describe("Message content validations", () => {
    it("accepts valid message content (length <= 512)", () => {
      expect(chatMessageSchema.parse("Hello world!")).toBe("Hello world!");
      expect(chatMessageSchema.parse("a".repeat(512))).toHaveLength(512);
    });

    it("rejects empty content and content exceeding 512 characters", () => {
      expect(() => chatMessageSchema.parse("")).toThrow();
      expect(() => chatMessageSchema.parse("a".repeat(513))).toThrow();
    });
  });

  describe("Group name validations", () => {
    it("accepts valid group names (length 1 to 100)", () => {
      expect(groupNameSchema.parse("Paris Trip")).toBe("Paris Trip");
      expect(groupNameSchema.parse("a".repeat(100))).toHaveLength(100);
    });

    it("rejects empty names and names exceeding 100 characters", () => {
      expect(() => groupNameSchema.parse("")).toThrow();
      expect(() => groupNameSchema.parse("a".repeat(101))).toThrow();
    });
  });

  describe("Group avatar URL validations", () => {
    it("accepts valid URLs and null values", () => {
      expect(avatarUrlSchema.parse("https://example.com/avatar.png")).toBe(
        "https://example.com/avatar.png"
      );
      expect(avatarUrlSchema.parse(null)).toBeNull();
    });

    it("rejects invalid URL patterns", () => {
      expect(() => avatarUrlSchema.parse("not-a-url")).toThrow();
    });
  });

  describe("Message Edit/Delete Timeframe Math", () => {
    const windowMs = 15 * 60 * 1000; // 15 minutes

    it("allows changes within the 15 minute window", () => {
      const justNow = new Date(Date.now() - 5 * 60 * 1000); // 5 minutes ago
      expect(isWithinTimeframe(justNow, windowMs)).toBe(true);
    });

    it("blocks changes outside the 15 minute window", () => {
      const longAgo = new Date(Date.now() - 16 * 60 * 1000); // 16 minutes ago
      expect(isWithinTimeframe(longAgo, windowMs)).toBe(false);
    });
  });
});
