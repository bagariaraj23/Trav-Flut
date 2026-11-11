import "dotenv/config";
import { PrismaClient } from "@prisma/client";
import { updateTripStatuses } from "./tripStatus";
import { createLogger, format, transports } from "winston";
import { logSchedulerStartupInfo } from "./startup-logger";

// Configure logger
const logger = createLogger({
  format: format.combine(format.timestamp(), format.json()),
  transports: [
    new transports.Console({
      format: format.combine(
        format.colorize(),
        format.printf(({ level, message, timestamp, ...meta }) => {
          const metaStr = Object.keys(meta).length ? JSON.stringify(meta) : '';
          return `${timestamp} [${level}]: ${message} ${metaStr}`;
        })
      ),
    }),
    new transports.File({ filename: "scheduler.log" }),
  ],
});

// Initialize Prisma
const prisma = new PrismaClient();

/**
 * Retry function with exponential backoff
 * @param fn Function to retry
 * @param maxAttempts Maximum number of attempts
 * @param initialDelayMs Initial delay in milliseconds
 */
async function retryWithBackoff<T>(
  fn: () => Promise<T>,
  maxAttempts: number = 3,
  initialDelayMs: number = 1000
): Promise<T> {
  let lastError: Error | unknown;
  
  for (let attempt = 1; attempt <= maxAttempts; attempt++) {
    try {
      return await fn();
    } catch (error) {
      lastError = error;
      
      if (attempt === maxAttempts) {
        logger.error(`All ${maxAttempts} attempts failed`, {
          attempt,
          error: error instanceof Error ? error.message : String(error),
        });
        throw error;
      }
      
      // Exponential backoff: 1s, 2s, 4s, etc.
      const delayMs = initialDelayMs * Math.pow(2, attempt - 1);
      logger.warn(`Attempt ${attempt} failed, retrying in ${delayMs}ms...`, {
        attempt,
        maxAttempts,
        error: error instanceof Error ? error.message : String(error),
      });
      
      await new Promise(resolve => setTimeout(resolve, delayMs));
    }
  }
  
  throw lastError;
}

/**
 * Main execution function - runs once and exits
 * Designed to be called by cron (e.g., every hour)
 */
async function runTripStatusUpdate(): Promise<void> {
  const startTime = Date.now();
  logger.info("Starting trip status update execution");

  try {
    // Test database connection first
    await prisma.$connect();
    logger.info("Database connection verified");

    // Execute the update with retry logic (now in UTC for consistent comparison with DB)
    const now = new Date();
    const result = await retryWithBackoff(
      () => updateTripStatuses(prisma, now),
      3, // 3 attempts
      1000 // Start with 1 second delay
    );

    const duration = Date.now() - startTime;
    logger.info("Trip status update completed successfully", {
      durationMs: duration,
      nowUtc: result.nowIso,
      endedCount: result.endedCount,
      ongoingCount: result.ongoingCount,
    });
  } catch (error) {
    const duration = Date.now() - startTime;
    logger.error("Trip status update failed after all retries", {
      durationMs: duration,
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    });
    throw error;
  } finally {
    // Always disconnect Prisma
    await prisma.$disconnect();
    logger.info("Database connection closed");
  }
}

/**
 * Handle shutdown gracefully
 */
async function shutdown(exitCode: number = 0) {
  logger.info("Shutting down scheduler...");
  try {
    await prisma.$disconnect();
  } catch (error) {
    logger.error("Error during shutdown", {
      error: error instanceof Error ? error.message : String(error),
    });
  }
  process.exit(exitCode);
}

// Main entry point
async function main() {
  try {
    logger.info("Starting scheduler (cron mode)...");
    
    // Log comprehensive startup information (without Redis)
    await logSchedulerStartupInfo(prisma);
    
    // Run the update once and exit
    await runTripStatusUpdate();
    
    logger.info("Scheduler execution completed successfully");
    await shutdown(0);
  } catch (error) {
    logger.error("Scheduler execution failed", {
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    });
    await shutdown(1);
  }
}

// Handle process signals
process.on("SIGTERM", () => shutdown(0));
process.on("SIGINT", () => shutdown(0));

// Handle uncaught errors
process.on("unhandledRejection", (reason, promise) => {
  logger.error("Unhandled promise rejection", {
    reason: reason instanceof Error ? reason.message : String(reason),
    promise: String(promise),
  });
  shutdown(1);
});

process.on("uncaughtException", (error) => {
  logger.error("Uncaught exception", {
    error: error.message,
    stack: error.stack,
  });
  shutdown(1);
});

// Start execution
main();
