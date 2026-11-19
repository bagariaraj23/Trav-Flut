import { describe, expect, it } from "vitest";
import { earlyAccessProgress, parseEarlyAccessBody } from "../../src/lib/earlyAccess";

describe("parseEarlyAccessBody", () => {
  it("requires a real email and a phone choice", () => {
    expect(parseEarlyAccessBody({ email: "not-an-email", platform: "android" })).toEqual({
      ok: false,
      error: "Enter a valid email.",
    });
    expect(parseEarlyAccessBody({ email: "a@b.co", platform: "web" })).toEqual({
      ok: false,
      error: "Choose Android or iPhone.",
    });
  });

  it("keeps Android and iPhone signups and a honeypot quiet", () => {
    expect(
      parseEarlyAccessBody({
        name: "Maya",
        email: "Maya@Example.com",
        platform: "android",
      })
    ).toEqual({
      ok: true,
      honeypot: false,
      name: "Maya",
      email: "maya@example.com",
      platform: "ANDROID",
    });
    expect(parseEarlyAccessBody({ email: "a@b.co", platform: "ios" })).toMatchObject({
      ok: true,
      platform: "IOS",
      name: null,
    });
    expect(parseEarlyAccessBody({ website: "spam", email: "a@b.co", platform: "android" })).toEqual({
      ok: true,
      honeypot: true,
    });
  });
});

describe("earlyAccessProgress", () => {
  it("caps the ring at the target and keeps the real count", () => {
    expect(earlyAccessProgress(42)).toEqual({ current: 42, target: 100, ratio: 0.42 });
    expect(earlyAccessProgress(140)).toEqual({ current: 140, target: 100, ratio: 1 });
    expect(earlyAccessProgress(-3)).toEqual({ current: 0, target: 100, ratio: 0 });
  });
});
