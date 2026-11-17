import { describe, expect, test } from "vitest";
import {
  MAX_CURATED_MEDIA,
  buildMemberFinalDraft,
  type DraftTrip,
} from "../src/memberFinalDraft";

describe("buildMemberFinalDraft", () => {
  test("stores an unpublished draft and keeps at most 12 of that person's photos", () => {
    const entries = Array.from({ length: 15 }, (_, index) => ({
      authorId: "member-1",
      contentText: null,
      createdAt: new Date(Date.UTC(2026, 0, 1 + index, 12)),
      locationName: null,
      media: {
        url: `https://cdn.example.com/photo-${index}.jpg`,
        type: "IMAGE",
        processingStatus: "COMPLETED",
        uploadedById: "member-1",
      },
      taggedUserIds: [],
      placeName: null,
    }));
    const trip: DraftTrip = {
      title: "Coast",
      startDate: new Date("2026-01-01T00:00:00.000Z"),
      endDate: new Date("2026-01-20T00:00:00.000Z"),
      destinations: ["Lisbon"],
      mood: null,
      entries,
      uploadedMedia: [],
    };

    const draft = buildMemberFinalDraft(trip, "member-1");

    expect(MAX_CURATED_MEDIA).toBe(12);
    expect(draft.generationStatus).toBe("DRAFT");
    expect(draft.curatedMedia).toHaveLength(12);
    expect(draft.curatedMedia[0]).toBe("https://cdn.example.com/photo-0.jpg");
    expect(draft.coverMediaUrl).toBe(draft.curatedMedia[0]);
    expect(draft.curatedMedia).not.toContain("https://cdn.example.com/photo-14.jpg");
  });
});
