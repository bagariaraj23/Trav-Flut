/**
 * Test setup: ensure essential env vars are present for test runs.
 * This file is loaded by Vitest before running tests.
 *
 * Sets default test environment variables if not already provided:
 * - NODE_ENV=test (should be set by test runner)
 * - DATABASE_URL: Test database connection string
 * - TEST_DATABASE_URL: Same as DATABASE_URL for test DB
 * - JWT_SECRET: Test JWT secret
 * - MAPBOX_ACCESS_TOKEN: Test Mapbox token
 */
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

export default function setupTests() {
  // Only run setup when NODE_ENV is test (or not set)
  const isTestEnv = !process.env.NODE_ENV || process.env.NODE_ENV === "test";

  if (!isTestEnv) return;

  // Load .env.test if present (local developer convenience)
  const envTestPath = path.resolve(process.cwd(), ".env.test");
  if (fs.existsSync(envTestPath)) {
    dotenv.config({ path: envTestPath });
  }

  // Don't silently fallback to a hard-coded DB URL. Require tests to provide DATABASE_URL.
  // In CI (GITHUB_ACTIONS or CI=true) we fail fast with clear instructions.
  const inCI = process.env.GITHUB_ACTIONS === "true" || process.env.CI === "true";

  if (!process.env.DATABASE_URL) {
    const msg = `DATABASE_URL is not set. Create a .env.test with DATABASE_URL (or export DATABASE_URL) before running tests.`;
    if (inCI) {
      // Fail early in CI to avoid accidentally connecting to wrong DB
      console.error(msg);
      throw new Error(msg);
    } else {
      // Local: warn developer and continue; tests will likely fail but message is clear
      // Developers can create a `.env.test` from `.env.test.example`.
      // eslint-disable-next-line no-console
      console.warn(msg);
    }
  }

  // Mirror TEST_DATABASE_URL to DATABASE_URL if not explicitly set
  if (!process.env.TEST_DATABASE_URL && process.env.DATABASE_URL) {
    process.env.TEST_DATABASE_URL = process.env.DATABASE_URL;
  }

  // Set minimal default secrets if missing (non-sensitive defaults for local dev)
  if (!process.env.JWT_SECRET) process.env.JWT_SECRET = "test-secret";
  if (!process.env.MAPBOX_ACCESS_TOKEN) process.env.MAPBOX_ACCESS_TOKEN = "test-mapbox-token";

  // Silence noisy logs in test environments unless DEBUG is explicitly set
  if (!process.env.DEBUG) process.env.DEBUG = "";
}

// Auto-run setup if this file is imported
setupTests();
