/**
 * Test setup: ensure essential env vars are present for test runs.
 * This file is loaded by Vitest before running any tests.
 *
 * IMPORTANT: Runs BEFORE application imports so Prisma sees a safe DATABASE_URL.
 *
 * - Loads `.env.test` only for file-based config.
 * - Clears inherited `DATABASE_URL` from the shell so production is never targeted by mistake.
 * - Sets `DATABASE_URL` exclusively from `TEST_DATABASE_URL`, which must point at a DB whose
 *   name ends with `_test` (see `src/lib/dbUrlSafety.ts`).
 */
import fs from "fs";
import path from "path";
import dotenv from "dotenv";
import { assertTestDatabaseUrl } from "../src/lib/dbUrlSafety";

export default function setupTests() {
  if (process.env.NODE_ENV !== "test") {
    (process.env as any).NODE_ENV = "test";
  }

  const envTestPath = path.resolve(process.cwd(), ".env.test");
  if (fs.existsSync(envTestPath)) {
    dotenv.config({ path: envTestPath });
  }

  delete process.env.DATABASE_URL;

  const inCI =
    process.env.GITHUB_ACTIONS === "true" || process.env.CI === "true";

  if (!process.env.TEST_DATABASE_URL) {
    const msg =
      "TEST_DATABASE_URL is not set in .env.test. Integration tests need it; unit tests still run without a database.";
    if (inCI) {
      console.error(msg);
      throw new Error(msg);
    }
    console.warn(msg);
  } else {
    assertTestDatabaseUrl(process.env.TEST_DATABASE_URL, "Vitest setup");
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
  }

  if (process.env.TEST_JWT_SECRET) {
    process.env.JWT_SECRET = process.env.TEST_JWT_SECRET;
  } else {
    process.env.JWT_SECRET =
      "test-jwt-secret-key-for-testing-only-do-not-use-in-production";
  }

  if (process.env.TEST_MAPBOX_ACCESS_TOKEN) {
    process.env.MAPBOX_ACCESS_TOKEN = process.env.TEST_MAPBOX_ACCESS_TOKEN;
  } else {
    process.env.MAPBOX_ACCESS_TOKEN = "test-mapbox-token";
  }

  if (process.env.TEST_REDIS_REST_URL) {
    process.env.REDIS_REST_URL = process.env.TEST_REDIS_REST_URL;
  }

  if (process.env.TEST_REDIS_REST_TOKEN) {
    process.env.REDIS_REST_TOKEN = process.env.TEST_REDIS_REST_TOKEN;
  }

  if (!process.env.DEBUG) process.env.DEBUG = "";

  if (process.env.DEBUG?.includes("test")) {
    console.log("[Test Setup] Environment configured:", {
      NODE_ENV: process.env.NODE_ENV,
      TEST_DATABASE_URL: process.env.TEST_DATABASE_URL?.replace(
        /:[^:@]+@/,
        ":****@"
      ),
      HAS_TEST_JWT_SECRET: !!process.env.TEST_JWT_SECRET,
      HAS_TEST_MAPBOX_TOKEN: !!process.env.TEST_MAPBOX_ACCESS_TOKEN,
    });
  }
}

setupTests();
