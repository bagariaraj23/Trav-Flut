/**
 * Test setup: ensure essential env vars are present for test runs.
 * This file is loaded by Vitest before running tests.
 *
 * IMPORTANT: This runs BEFORE any application code is imported.
 * This ensures .env.test is loaded before src/env.ts validates environment.
 *
 * ARCHITECTURE:
 * - Tests use TEST_* prefixed variables from .env.test ONLY
 * - In test mode, we map TEST_* variables to non-prefixed versions for Prisma/application code
 * - This ensures complete separation: tests never touch production variables
 *
 * Required TEST_* variables in .env.test:
 * - TEST_DATABASE_URL: Test database connection string
 * - TEST_JWT_SECRET: Test JWT secret
 * - TEST_MAPBOX_ACCESS_TOKEN: Test Mapbox token
 * - TEST_REDIS_REST_URL: (optional) Test Redis URL
 * - TEST_REDIS_REST_TOKEN: (optional) Test Redis token
 */
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

export default function setupTests() {
  // Force NODE_ENV to test mode for all tests
  // This ensures no production code paths are executed
  if (process.env.NODE_ENV !== "test") {
    Object.defineProperty(process.env, 'NODE_ENV', {
      value: 'test',
      writable: true,
      configurable: true
    });
  }

  // Load .env.test FIRST
  const envTestPath = path.resolve(process.cwd(), ".env.test");
  if (fs.existsSync(envTestPath)) {
    dotenv.config({ path: envTestPath });
  }

  // In test mode, map TEST_* variables to non-prefixed versions
  // This allows Prisma and application code to work without knowing about TEST_* prefix
  
  // Check for required TEST_* variables
  const inCI = process.env.GITHUB_ACTIONS === "true" || process.env.CI === "true";
  
  if (!process.env.TEST_DATABASE_URL) {
    const msg = `TEST_DATABASE_URL is not set in .env.test. Tests require TEST_* prefixed variables.`;
    if (inCI) {
      console.error(msg);
      throw new Error(msg);
    } else {
      console.warn(msg);
    }
  }

  // Map TEST_* variables to non-prefixed versions for application code
  // This is ONLY done in test mode - production code never sees TEST_* variables
  if (process.env.TEST_DATABASE_URL) {
    process.env.DATABASE_URL = process.env.TEST_DATABASE_URL;
  }
  
  if (process.env.TEST_JWT_SECRET) {
    process.env.JWT_SECRET = process.env.TEST_JWT_SECRET;
  } else {
    // Provide safe test default if not in .env.test
    process.env.JWT_SECRET = "test-jwt-secret-key-for-testing-only-do-not-use-in-production";
  }
  
  if (process.env.TEST_MAPBOX_ACCESS_TOKEN) {
    process.env.MAPBOX_ACCESS_TOKEN = process.env.TEST_MAPBOX_ACCESS_TOKEN;
  } else {
    // Provide safe test default if not in .env.test
    process.env.MAPBOX_ACCESS_TOKEN = "test-mapbox-token";
  }
  
  // Optional Redis variables
  if (process.env.TEST_REDIS_REST_URL) {
    process.env.REDIS_REST_URL = process.env.TEST_REDIS_REST_URL;
  }
  
  if (process.env.TEST_REDIS_REST_TOKEN) {
    process.env.REDIS_REST_TOKEN = process.env.TEST_REDIS_REST_TOKEN;
  }

  // Silence noisy logs in test environments unless DEBUG is explicitly set
  if (!process.env.DEBUG) process.env.DEBUG = "";

  // Log test environment status (helpful for debugging)
  if (process.env.DEBUG?.includes('test')) {
    console.log('[Test Setup] Environment configured:', {
      NODE_ENV: process.env.NODE_ENV,
      TEST_DATABASE_URL: process.env.TEST_DATABASE_URL?.replace(/:[^:@]+@/, ':****@'), // Mask password
      HAS_TEST_JWT_SECRET: !!process.env.TEST_JWT_SECRET,
      HAS_TEST_MAPBOX_TOKEN: !!process.env.TEST_MAPBOX_ACCESS_TOKEN,
    });
  }
}

setupTests();