import { describe, expect, it } from "vitest";
import { parseSupportBody } from "../../src/lib/supportMessage";

describe("parseSupportBody", () => {
  it("asks for a real message", () => {
    const result = parseSupportBody({ message: "hi", email: "a@b.co" });
    expect(result).toEqual({
      ok: false,
      error: "Write at least a few words so we can help.",
    });
  });

  it("rejects a broken email", () => {
    const result = parseSupportBody({
      message: "The trip map will not open.",
      email: "not-an-email",
    });
    expect(result.ok).toBe(false);
  });

  it("accepts a message and keeps a honeypot quiet", () => {
    expect(
      parseSupportBody({
        name: "Maya",
        email: "Maya@Example.com",
        message: "I cannot leave a trip while a balance is open.",
      })
    ).toMatchObject({
      ok: true,
      honeypot: false,
      name: "Maya",
      email: "maya@example.com",
    });

    expect(parseSupportBody({ website: "spam", message: "ignore" })).toEqual({
      ok: true,
      honeypot: true,
    });
  });
});
