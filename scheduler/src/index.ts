import { PrismaClient } from "@prisma/client";
import { updateTripStatuses } from "./tripStatus";

import { Queue, Worker, Job } from "bullmq";
import { Redis } from "ioredis";
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

// Initialize Redis connection
const redisConnection = new Redis(
  process.env.REDIS_URL || "redis://localhost:6379"
);

// Initialize Prisma
const prisma = new PrismaClient();

// Create queues
const tripStatusQueue = new Queue("tripStatus", {
  connection: redisConnection,
});

// Process trip status updates
const tripStatusWorker = new Worker(
  "tripStatus",
  async (job: Job) => {
    try {
      logger.info("Starting trip status update job", { jobId: job.id });

      const now = new Date();
      await updateTripStatuses(prisma, now);

      logger.info("Trip status update job completed", { jobId: job.id });
    } catch (error) {
      logger.error("Trip status update job failed", {
        jobId: job.id,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  },
  {
    connection: redisConnection,
    // Add basic retry/attempts configuration so transient failures are retried
    autorun: true,
    concurrency: 1,
    // Worker options can be extended as needed
  }
);

// Schedule jobs
async function scheduleJobs() {
  // Schedule trip status updates every hour
  // Use a cron expression and a fixed jobId to avoid accidentally scheduling
  // duplicate repeatable jobs if the scheduler starts multiple times.
  await tripStatusQueue.add(
    "updateTripStatus",
    {},
    {
      repeat: {
        // Run every hour (3600000 ms). Using 'every' avoids cron typing issues
        every: 60 * 60 * 1000,
      },
      jobId: "updateTripStatus:repeat:hourly",
    }
  );

  logger.info("Jobs scheduled successfully");
}

// Handle shutdown
async function shutdown() {
  logger.info("Shutting down scheduler...");
  await tripStatusWorker.close();
  await redisConnection.quit();
  await prisma.$disconnect();
  process.exit(0);
}

// Start scheduler
async function start() {
  try {
    logger.info("Starting scheduler service...");
    
    // Log comprehensive startup information
    await logSchedulerStartupInfo(prisma, redisConnection);
    
    // Test connections before proceeding
    await prisma.$connect();
    await redisConnection.ping();
    
    logger.info("All connections verified, scheduling jobs...");
    await scheduleJobs();
    logger.info("Scheduler service started successfully");
  } catch (error) {
    logger.error("Failed to start scheduler", {
      error: error instanceof Error ? error.message : String(error),
      stack: error instanceof Error ? error.stack : undefined,
    });
    await shutdown();
    process.exit(1);
  }
}

// Handle process signals
process.on("SIGTERM", shutdown);
process.on("SIGINT", shutdown);

// Start the service
start();
