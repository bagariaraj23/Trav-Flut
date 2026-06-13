import { describe, expect, it } from "vitest";
import { randomUUID } from "crypto";
import {
  completeProfileSchema,
  createThreadEntrySchema,
  createTripSchema,
  loginSchema,
  patchThreadEntryTextSchema,
} from "../../src/lib/validation";

function daysFromNow(days: number) {
  const d = new Date();
  d.setUTCDate(d.getUTCDate() + days);
  return d.toISOString();
}

describe("Auth validation schemas", () => {
  it("normalizes email login input and username login input", () => {
    expect(
      loginSchema.parse({ email: " USER@Example.COM ", password: "x" }).email
    ).toBe("user@example.com");
    expect(loginSchema.parse({ email: " Mixed_User ", password: "x" }).email).toBe(
      "mixed_user"
    );
  });

  it("rejects invalid complete-profile passwords and normalizes username", () => {
    expect(() =>
      completeProfileSchema.parse({
        username: "valid_user",
        password: "weak",
        name: "Valid User",
      })
    ).toThrow();

    expect(
      completeProfileSchema.parse({
        username: "Valid_User",
        password: "Password123!",
        name: "Valid User",
      }).username
    ).toBe("valid_user");
  });
});

describe("Trip validation schemas", () => {
  it("accepts a valid future trip with destination places", () => {
    const result = createTripSchema.parse({
      title: "  Japan Spring  ",
      description: "  Cherry blossoms  ",
      startDate: daysFromNow(2),
      endDate: daysFromNow(5),
      destinationPlaceIds: [randomUUID(), randomUUID()],
      mood: "ADVENTURE",
      type: "GROUP",
    });

    expect(result.title).toBe("Japan Spring");
    expect(result.description).toBe("Cherry blossoms");
    expect(result.destinationPlaceIds).toHaveLength(2);
  });

  it("rejects invalid date order and missing destinations", () => {
    expect(() =>
      createTripSchema.parse({
        title: "Bad Trip",
        startDate: daysFromNow(5),
        endDate: daysFromNow(2),
        destinationPlaceIds: [randomUUID()],
      })
    ).toThrow("End date must be after start date");

    expect(() =>
      createTripSchema.parse({
        title: "No Destination",
        startDate: daysFromNow(2),
        endDate: daysFromNow(3),
        destinationPlaceIds: [],
      })
    ).toThrow("At least one destination is required");
  });
});

describe("Thread entry validation schemas", () => {
  it("enforces type-specific required fields", () => {
    expect(
      createThreadEntrySchema.parse({
        type: "TEXT",
        contentText: " hello thread ",
      }).contentText
    ).toBe("Hello thread");

    expect(() =>
      createThreadEntrySchema.parse({ type: "MEDIA", contentText: "missing media" })
    ).toThrow("Required fields missing for entry type");

    expect(() =>
      createThreadEntrySchema.parse({ type: "LOCATION" })
    ).toThrow("Required fields missing for entry type");
  });

  it("normalizes patched text and rejects blank edits", () => {
    expect(
      patchThreadEntryTextSchema.parse({ contentText: " updated note " })
        .contentText
    ).toBe("Updated note");
    expect(() =>
      patchThreadEntryTextSchema.parse({ contentText: "" })
    ).toThrow("Content is required");
  });
});
