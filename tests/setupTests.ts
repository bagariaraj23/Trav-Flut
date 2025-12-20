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
export default function setupTests() {
  // Only set defaults if NODE_ENV is test or not set (assume test mode)
  const isTestEnv = !process.env.NODE_ENV || process.env.NODE_ENV === "test";

  if (isTestEnv) {
    // Set test database URL if not provided
    if (!process.env.DATABASE_URL) {
      process.env.DATABASE_URL =
        "postgresql://postgres:pass@localhost:5432/tripthread_test?schema=public";
    }

    // Set TEST_DATABASE_URL to match DATABASE_URL if not explicitly set
    if (!process.env.TEST_DATABASE_URL) {
      process.env.TEST_DATABASE_URL = process.env.DATABASE_URL;
    }

    // Set test JWT secret if not provided
    if (!process.env.JWT_SECRET) {
      process.env.JWT_SECRET = "test-secret";
    }

    // Set test Mapbox token if not provided
    if (!process.env.MAPBOX_ACCESS_TOKEN) {
      process.env.MAPBOX_ACCESS_TOKEN = "test-mapbox-token";
    }

    // Silence noisy logs in test environments
    if (!process.env.DEBUG) {
      process.env.DEBUG = "";
    }
  }
}

// Auto-run setup if this file is imported
setupTests();
