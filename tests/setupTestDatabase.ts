/**
 * Test Database Setup Utility
 * Creates the test database if it doesn't exist
 * This ensures tests can run without manual database creation
 */
import { PrismaClient } from "@prisma/client";
import { execSync } from "child_process";

export async function ensureTestDatabase() {
  // Use TEST_DATABASE_URL - this is the source of truth for tests
  const dbUrl = process.env.TEST_DATABASE_URL;
  if (!dbUrl) {
    throw new Error(
      "TEST_DATABASE_URL is not set in .env.test. Tests require TEST_* prefixed variables."
    );
  }

  // Extract database name from URL
  // Format: postgresql://user:password@host:port/database
  const urlMatch = dbUrl.match(/postgresql:\/\/[^/]+\/([^?]+)/);
  if (!urlMatch) {
    throw new Error(`Invalid DATABASE_URL format: ${dbUrl}`);
  }

  const dbName = urlMatch[1];

  // Extract connection info for admin connection (without database name)
  const adminUrl = dbUrl.replace(/\/[^/]+(\?|$)/, "/postgres$1");

  try {
    // Try to connect to the test database
    // In Prisma v7, we rely on DATABASE_URL from environment (already set)
    const testPrisma = new PrismaClient();

    await testPrisma.$connect();
    await testPrisma.$disconnect();

    // Database exists, we're good
    return;
  } catch (error: any) {
    // Database doesn't exist, create it
    if (error.code === "P1003" || error.message?.includes("does not exist")) {
      console.log(`Creating test database: ${dbName}`);

      // Store original URL for restoration
      const originalUrl = process.env.DATABASE_URL;

      try {
        // Connect to postgres database to create the test database
        // Temporarily override DATABASE_URL for admin connection
        process.env.DATABASE_URL = adminUrl;
        const adminPrisma = new PrismaClient();

        await adminPrisma.$connect();

        // Create database using raw SQL
        await adminPrisma.$executeRawUnsafe(`CREATE DATABASE "${dbName}";`);

        await adminPrisma.$disconnect();

        // Restore original DATABASE_URL
        process.env.DATABASE_URL = originalUrl;

        console.log(`Test database '${dbName}' created successfully`);
      } catch (createError: any) {
        // Restore original DATABASE_URL on error
        process.env.DATABASE_URL = originalUrl;

        if (createError.code === "42P04") {
          // Database already exists (race condition)
          console.log(`Database '${dbName}' already exists`);
        } else {
          throw new Error(
            `Failed to create test database '${dbName}': ${createError.message}\n` +
              `Make sure PostgreSQL is running and you have CREATE DATABASE permissions.\n` +
              `You can also create it manually: CREATE DATABASE ${dbName};`
          );
        }
      }
    } else {
      // Some other connection error
      throw error;
    }
  }
}
