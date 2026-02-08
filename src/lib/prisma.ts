import { PrismaClient } from "@prisma/client";

const globalForPrisma = globalThis as unknown as {
  prisma: PrismaClient | undefined;
};

const prismaClient =
  globalForPrisma.prisma ??
  new PrismaClient({
    log:
      process.env.NODE_ENV === "development"
        ? ["query", "error", "warn"]
        : ["error"],
  });

// Connection will be tested by startup logger
// Don't exit on error here - let the startup logger handle it
prismaClient
  .$connect()
  .then(() => {
    // Connection successful - startup logger will log this
  })
  .catch((e) => {
    // Error will be caught and logged by startup logger
    console.error(
      "Database connection error (will be logged by startup logger):",
      e
    );
  });

if (process.env.NODE_ENV !== "production")
  globalForPrisma.prisma = prismaClient;

export const prisma = prismaClient;
