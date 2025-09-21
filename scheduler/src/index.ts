import { PrismaClient } from '@prisma/client';

// Define TripStatus enum manually (update values if your schema differs)
enum TripStatus {
    UPCOMING = 'UPCOMING',
    ONGOING = 'ONGOING',
    ENDED = 'ENDED'
}
import { Queue, Worker, Job } from 'bullmq';
import { Redis } from 'ioredis';
import { createLogger, format, transports } from 'winston';

// Configure logger
const logger = createLogger({
    format: format.combine(
        format.timestamp(),
        format.json()
    ),
    transports: [
        new transports.Console(),
        new transports.File({ filename: 'scheduler.log' })
    ]
});

// Initialize Redis connection
const redisConnection = new Redis(process.env.REDIS_URL || 'redis://localhost:6379');

// Initialize Prisma
const prisma = new PrismaClient();

// Create queues
const tripStatusQueue = new Queue('tripStatus', { connection: redisConnection });

// Process trip status updates
const tripStatusWorker = new Worker('tripStatus', async (job: Job) => {
    try {
        logger.info('Starting trip status update job', { jobId: job.id });

        const now = new Date();

        // Update trips that have ended
        await prisma.trip.updateMany({
            where: {
                endDate: {
                    lte: now
                },
                status: TripStatus.ONGOING
            },
            data: {
                status: TripStatus.ENDED
            }
        });

        // Update trips that have started
        await prisma.trip.updateMany({
            where: {
                startDate: {
                    lte: now
                },
                status: TripStatus.UPCOMING
            },
            data: {
                status: TripStatus.ONGOING
            }
        });

        logger.info('Trip status update job completed', { jobId: job.id });
    } catch (error) {
        logger.error('Trip status update job failed', {
            jobId: job.id,
            error: error instanceof Error ? error.message : String(error)
        });
        throw error;
    }
}, { connection: redisConnection });

// Schedule jobs
async function scheduleJobs() {
    // Schedule trip status updates every hour
    await tripStatusQueue.add('updateTripStatus', {}, {
        repeat: {
            pattern: '0 * * * *' // Every hour
        }
    });

    logger.info('Jobs scheduled successfully');
}

// Handle shutdown
async function shutdown() {
    logger.info('Shutting down scheduler...');
    await tripStatusWorker.close();
    await redisConnection.quit();
    await prisma.$disconnect();
    process.exit(0);
}

// Start scheduler
async function start() {
    try {
        logger.info('Starting scheduler service...');
        await scheduleJobs();
        logger.info('Scheduler service started successfully');
    } catch (error) {
        logger.error('Failed to start scheduler', {
            error: error instanceof Error ? error.message : String(error)
        });
        await shutdown();
    }
}

// Handle process signals
process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

// Start the service
start();