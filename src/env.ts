import { z } from "zod";
import fs from "fs";
import path from "path";
import dotenv from "dotenv";

// In test mode, we expect setupTests.ts to have already:
// 1. Loaded .env.test (with TEST_* prefixed variables)
// 2. Mapped TEST_* variables to non-prefixed versions (DATABASE_URL, JWT_SECRET, etc.)
// 3. Set NODE_ENV=test
// 
// So by the time this module loads, DATABASE_URL, JWT_SECRET, etc. should already be set
// from TEST_DATABASE_URL, TEST_JWT_SECRET, etc. via setupTests.ts
//
// We don't load .env.test here because setupTests.ts already did that.
// We don't load .env here because tests should never use production variables.

// Define environment schema with Zod for validation
const envSchema = z.object({
  // Node environment
  NODE_ENV: z
    .enum(["development", "test", "production"])
    .default("development"),

  // Core app vars (add more as needed)
  DATABASE_URL: z.string().min(1),
  JWT_SECRET: z.string().min(1),

  // Map integration
  MAPBOX_ACCESS_TOKEN: z.string().min(1),

  // Redis (Upstash REST recommended)
  REDIS_REST_URL: z.string().url().optional(),
  REDIS_REST_TOKEN: z.string().min(1).optional(),
});

// Parse and validate environment variables
const parsed = envSchema.safeParse(process.env);

let validatedEnv: z.infer<typeof envSchema>;

if (!parsed.success) {
  // In test mode, provide defaults instead of exiting
  // This allows tests to run even if some env vars are missing
  if (process.env.NODE_ENV === "test") {
    console.warn(
      "Invalid environment variables in test mode:",
      JSON.stringify(parsed.error.format(), null, 2)
    );
    
    // Provide test defaults for missing required fields
    const testDefaults = {
      NODE_ENV: "test" as const,
      DATABASE_URL: process.env.DATABASE_URL || "postgresql://postgres:postgres@localhost:5432/tripthread_test",
      JWT_SECRET: process.env.JWT_SECRET || "test-jwt-secret-key-for-testing-only",
      MAPBOX_ACCESS_TOKEN: process.env.MAPBOX_ACCESS_TOKEN || "test-mapbox-token",
      REDIS_REST_URL: process.env.REDIS_REST_URL,
      REDIS_REST_TOKEN: process.env.REDIS_REST_TOKEN,
    };
    
    const testParsed = envSchema.safeParse(testDefaults);
    if (testParsed.success) {
      validatedEnv = testParsed.data;
    } else {
      // If even defaults fail, throw error (better for tests than exit)
      throw new Error(
        `Invalid test environment: ${JSON.stringify(parsed.error.format(), null, 2)}`
      );
    }
  } else {
    // Production/development: strict validation
    console.error(
      "Invalid environment variables:",
      JSON.stringify(parsed.error.format(), null, 2)
    );
    process.exit(1);
  }
} else {
  validatedEnv = parsed.data;
}

// Export validated and typed env object
export const ENV = validatedEnv as Readonly<z.infer<typeof envSchema>>;

// Log environment status in development
if (ENV.NODE_ENV === "development") {
  console.log("[Next.js] Environment loaded:", {
    NODE_ENV: ENV.NODE_ENV,
  });
}
