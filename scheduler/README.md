# TripThread Scheduler

## Overview

The scheduler is a lightweight Node.js (TypeScript) service designed to run as a **cron job**. It performs periodic maintenance tasks to transition `Trip` records between statuses over time:

- UPCOMING -> ONGOING when `startDate <= now < endDate`
- ONGOING/UPCOMING -> ENDED when `endDate <= now`

## Architecture

**Key Design Decision: No Redis Dependency**

The scheduler runs as a **simple cron-executable script** that:
- Executes once per invocation (designed for cron scheduling)
- Connects directly to PostgreSQL via Prisma
- Includes retry logic with exponential backoff for transient failures
- Exits after completion (no long-running process)

This design ensures:
- **Zero Redis usage** - All Upstash Redis budget is available for API caching
- **Simple operation** - No queue management, workers, or Redis connections
- **Reliable execution** - Database is the source of truth
- **Easy deployment** - Works with Railway Cron, GitHub Actions, or any cron service

Key file(s):

- `src/index.ts`: Main entry point - runs once, calls `updateTripStatuses`, and exits
- `src/tripStatus.ts`: Contains `updateTripStatuses(prisma, now)` which applies the status transitions in a Prisma transaction

## Environment

Required environment variables:

```
DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DB_NAME
LOG_LEVEL=info  # optional
```

**Note:** `REDIS_URL` is no longer required or used.

## Local Development

1. Install and generate Prisma client:

```bash
cd scheduler
npm install
npm run generate
```

2. Run the scheduler directly (simulates cron execution):

```bash
npm run dev
# or
npm start  # after building
```

3. Ensure your Next.js app and DB are running. Create trips with various `startDate`/`endDate` and observe automatic transitions.

## Deployment Options

### Option 1: Railway Cron

Configure a Railway Cron job to run:
```bash
0 * * * *  # Every hour
```

Command:
```bash
cd scheduler && npm start
```

### Option 2: GitHub Actions

Create `.github/workflows/scheduler.yml`:
```yaml
name: Trip Status Scheduler
on:
  schedule:
    - cron: '0 * * * *'  # Every hour
  workflow_dispatch:  # Allow manual trigger

jobs:
  update-trips:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
        with:
          node-version: '18'
      - run: cd scheduler && npm install && npm run build
      - run: cd scheduler && npm start
        env:
          DATABASE_URL: ${{ secrets.DATABASE_URL }}
```

### Option 3: Upstash QStash

Use QStash to trigger HTTP endpoint that runs the scheduler.

### Option 4: Manual Execution

For testing or manual runs:
```bash
cd scheduler
npm start
```

## Testing

We use Jest + ts-jest.

Unit tests:

- File: `tests/tripStatus.unit.test.ts`
- Covers: ENDED on `endDate <= now`, ONGOING on `startDate <= now < endDate`, and boundary behavior at exact `endDate`.
  Run:

```bash
npm run test:unit
```

Integration test:

- File: `tests/tripStatus.integration.test.ts`
- Tests direct execution of `updateTripStatuses` (no Redis required)
- Run:

```bash
npm run test:e2e
```

## Retry Logic

The scheduler includes built-in retry logic:
- **3 attempts** with exponential backoff
- Delays: 1s, 2s, 4s
- Only retries on transient database errors
- Logs all attempts for debugging

## Operational Notes

- **Time resolution**: Status changes use `Date` comparisons. If your domain uses date-only semantics, normalize at the API boundary to midnight UTC to avoid off-by-hours.
- **Immediate transitions**: If a trip is created with `startDate == now`, consider computing initial status at creation time in the API; otherwise, rely on the scheduler's hourly execution.
- **No overlapping executions**: Since this runs as a cron job, each execution completes before the next one starts. No need for locks or concurrency control.
- **Health checks**: The scheduler logs comprehensive startup information and exits with appropriate codes (0 = success, 1 = failure).

## Why No Redis?

**Problem**: BullMQ (Redis-based job queue) was consuming the Upstash free tier's 500k command limit through constant polling, heartbeats, and queue management.

**Solution**: This cron-based approach:
- Uses **zero Redis commands** - All budget available for API caching
- Simpler architecture - No queue management complexity
- More reliable - Database is the source of truth
- Easier to debug - Single execution, clear logs

The API continues to use Upstash Redis for caching (place lookups, search results, rate limiting), but the scheduler runs completely independently.
