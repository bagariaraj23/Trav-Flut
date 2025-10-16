# TripThread Scheduler

## Overview

The scheduler is a Node.js (TypeScript) service that uses BullMQ (Redis-backed queues) to perform periodic maintenance tasks. Its primary job is to transition `Trip` records between statuses over time:

- UPCOMING -> ONGOING when `startDate <= now < endDate`
- ONGOING/UPCOMING -> ENDED when `endDate <= now`

## Architecture

- Queue: `tripStatus` (repeatable job) using BullMQ
- Worker: single-concurrency worker to avoid overlapping updates
- Persistence: Prisma Client connected to the main Postgres database
- Logging: Winston (console + file `scheduler.log`)

Key file(s):

- `src/index.ts`: boots Redis connection, creates the queue/worker, schedules the repeatable job
- `src/tripStatus.ts`: contains `updateTripStatuses(prisma, now)` which applies the status transitions in a Prisma transaction

## Environment

Copy `.env.example` to `.env` and fill values:

```
REDIS_URL=redis://localhost:6379
DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DB_NAME
LOG_LEVEL=info
# SCHEDULER_REPEAT_EVERY_MS=60000
# REDIS_E2E=1
```

## Local Development

1. Start Redis (Docker):

```
docker run -d -p 6379:6379 redis:alpine
```

2. Install and generate Prisma client:

```
cd scheduler
npm install
npm run generate
```

3. Start the scheduler:

```
npm run dev
```

4. Ensure your Next.js app and DB are running. Create trips with various `startDate`/`endDate` and observe automatic transitions.

## Trigger a one-off run

You can enqueue a manual job without waiting for the repeat interval:

```
node -e "const { Queue } = require('bullmq'); const { Redis } = require('ioredis'); const q=new Queue('tripStatus',{connection:new Redis(process.env.REDIS_URL||'redis://localhost:6379')}); q.add('updateTripStatus',{}, { jobId:'manual:'+Date.now() }).then(()=>q.close());"
```

## Testing

We use Jest + ts-jest.

Unit tests:

- File: `tests/tripStatus.unit.test.ts`
- Covers: ENDED on `endDate <= now`, ONGOING on `startDate <= now < endDate`, and boundary behavior at exact `endDate`.
  Run:

```
npm run test:unit
```

Integration test (optional, requires Redis):

- File: `tests/tripStatus.integration.test.ts`
- Uses BullMQ with a real Redis to enqueue and process a job that calls `updateTripStatuses`.
- Skipped by default; enable with env flag and run:

```
REDIS_E2E=1 npm run test:e2e
```

## Why one test shows as skipped

Your Jest summary shows “1 skipped” because the integration test is designed to skip unless `REDIS_E2E=1` is set. This avoids flakiness when Redis is not available during normal unit testing.

## Operational Notes

- Time resolution: status changes use `Date` comparisons. If your domain uses date-only semantics, normalize at the API boundary to midnight UTC to avoid off-by-hours.
- Immediate transitions: if a trip is created with `startDate == now`, consider computing initial status at creation time in the API; otherwise, rely on the scheduler’s repeat interval.
- Overlaps/restarts: worker concurrency is 1 and repeatable job uses a fixed `jobId` to prevent duplicate enqueues across restarts.
