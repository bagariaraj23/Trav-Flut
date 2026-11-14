# TripThread Scheduler

A lightweight Node.js (TypeScript) service that automatically transitions trip statuses based on time. The process runs **once and exits**. Something outside it decides when to start it again: production cron (the examples below use hourly), or the local Docker loop (every `SCHEDULER_INTERVAL_SECONDS`, default 300).

## What It Does

The scheduler automatically updates trip statuses:
- **UPCOMING → ONGOING** when `startDate <= now < endDate`
- **UPCOMING/ONGOING → ENDED** when `endDate <= now`

When a due trip ends, it also creates one unpublished final-post draft per current member, marked `DRAFT`, with up to 12 of that person's photos. The text and photo choice live in `src/memberFinalDraft.ts`, which the API imports, so ending the trip in the app writes the same draft. A member who already has a row is left alone. The scheduler does not publish the post.

## Quick Start

### Prerequisites

- Node.js 18+
- PostgreSQL database
- Prisma schema generated

### Installation

```bash
cd scheduler
npm install
npm run generate  # Generate Prisma client
```

### Run Locally

```bash
# Development mode (with watch)
npm run dev

# Production mode (after build)
npm run build
npm start
```

## Architecture

**Key Design: Zero Redis Dependency**

The scheduler runs as a **simple cron-executable script** that:
- Executes once per invocation, then exits (no in-process timer)
- Connects directly to PostgreSQL via Prisma
- Includes retry logic with exponential backoff
- Open-ended trips (`endDate` null) start on time and stay ongoing until an end is set
- Local Docker starts the same script in a loop; it does not turn this process into a resident worker

**Benefits:**
- ✅ **Zero Redis usage** - All Upstash Redis budget available for API caching
- ✅ **Simple operation** - No queue management or workers
- ✅ **Reliable** - Database is the source of truth
- ✅ **Easy deployment** - Works with any cron service

### Core Files

- `src/index.ts` - Main entry point, runs once and exits
- `src/tripStatus.ts` - Core logic: `updateTripStatuses(prisma, now)`
- `src/startup-logger.ts` - Startup diagnostics and logging

For detailed architecture information, see [SCHEDULER_ARCHITECTURE.md](./SCHEDULER_ARCHITECTURE.md).

## Environment Variables

```bash
DATABASE_URL=postgres://USER:PASSWORD@HOST:5432/DB_NAME
LOG_LEVEL=info  # optional, defaults to 'info'
```

**Note:** `REDIS_URL` is **not required** - the scheduler uses zero Redis commands.

## Deployment

### Local Docker

`docker compose up --build -d` builds `scheduler/Dockerfile` and starts the container only after the API healthcheck passes (so migrations have been applied). The container command is a shell loop around the one-shot script:

```sh
while true; do node dist/index.js || echo 'Scheduler run failed'; sleep "$SCHEDULER_INTERVAL_SECONDS"; done
```

`SCHEDULER_INTERVAL_SECONDS` defaults to 300 and `TZ` is UTC. A failed run is logged and retried on the next interval. The script itself is unchanged. Confirm a run with `docker compose logs scheduler`.

Production does not use this Compose loop. Use one of the cron options below, or the Railway scheduler service.

### Option 1: Railway Cron (Recommended)

Configure in Railway dashboard or `railway.json`:

```json
{
  "cron": {
    "schedule": "0 * * * *",
    "command": "cd scheduler && npm start"
  }
}
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

### Option 3: System Cron

```bash
# Add to crontab: crontab -e
0 * * * * cd /path/to/project/scheduler && npm start >> /var/log/scheduler.log 2>&1
```

### Option 4: Manual Execution

For testing or manual runs:

```bash
cd scheduler
npm start
```

## Testing

### Unit Tests

Tests the core status transition logic:

```bash
npm run test:unit
```

**File:** `tests/tripStatus.unit.test.ts`
- Tests ENDED transitions on `endDate <= now`
- Tests ONGOING transitions on `startDate <= now < endDate`
- Tests boundary conditions

### Integration Tests

Tests direct execution with database:

```bash
npm run test:e2e
```

**File:** `tests/tripStatus.integration.test.ts`
- Tests full `updateTripStatuses()` execution
- Requires database connection
- No Redis required

## Features

### Retry Logic

Built-in retry with exponential backoff:
- **3 attempts** maximum
- Delays: 1s, 2s, 4s
- Only retries on transient database errors
- All attempts logged for debugging

### Error Handling

- Graceful shutdown on SIGTERM/SIGINT
- Uncaught exception handling
- Exit codes: 0 (success), 1 (failure)
- Comprehensive error logging

### Logging

- Winston logger with JSON and console formats
- Logs to `scheduler.log` file
- Startup diagnostics included
- Performance metrics logged

## Operational Notes

### Time Resolution

Status changes use `Date` comparisons. If your domain uses date-only semantics, normalize at the API boundary to midnight UTC to avoid off-by-hours issues.

### Immediate Transitions

If a trip is created with `startDate == now`, the API should compute initial status at creation time. Otherwise the next scheduler run applies it. An hourly cron can lag up to an hour; the local Docker loop defaults to five minutes because start and end instants are minute-precision UTC.

### Concurrency

Since this runs as a cron job, each execution completes before the next one starts. No locks or concurrency control needed.

### Health Checks

The scheduler logs comprehensive startup information and exits with appropriate codes. Monitor logs to verify execution.

## Why No Redis?

**Problem:** BullMQ (Redis-based job queue) consumed 86% of the Upstash free tier's 500k command limit through constant polling, heartbeats, and queue management.

**Solution:** This cron-based approach:
- Uses **zero Redis commands** ✅
- Simpler architecture ✅
- More reliable (database is source of truth) ✅
- Easier to debug ✅

The API continues to use Upstash Redis for caching, but the scheduler runs completely independently.

## Troubleshooting

### Scheduler Not Running

1. Local Docker: `docker compose logs scheduler` and confirm the backend is healthy (`docker compose ps`). The scheduler waits for that healthcheck.
2. Cron: check the cron service is configured and `DATABASE_URL` is set
3. Check logs: `scheduler.log` or the cron service logs
4. Test one run: `npm start` inside `scheduler/`

### Status Not Updating

1. Verify trips have correct `startDate`/`endDate`
2. Check database connection
3. Review logs for errors
4. Ensure the trigger is actually firing (hourly cron, or the Docker loop every `SCHEDULER_INTERVAL_SECONDS`)

### Database Connection Errors

1. Verify `DATABASE_URL` format
2. Check database is accessible
3. Review retry logic logs
4. Ensure Prisma client is generated

## Development

### Project Structure

```
scheduler/
├── src/
│   ├── index.ts           # Main entry point
│   ├── tripStatus.ts      # Core status update logic
│   └── startup-logger.ts  # Startup diagnostics
├── tests/
│   ├── tripStatus.unit.test.ts
│   └── tripStatus.integration.test.ts
├── dist/                  # Compiled JavaScript
├── package.json
├── tsconfig.json
├── jest.config.ts
├── Dockerfile
└── start.sh               # Railway-compatible start script
```

### Building

```bash
npm run build
```

Output: `dist/index.js`

### Scripts

- `npm run dev` - Run with watch mode (development)
- `npm run build` - Compile TypeScript
- `npm start` - Run compiled code
- `npm run generate` - Generate Prisma client
- `npm run test:unit` - Run unit tests
- `npm run test:e2e` - Run integration tests

## Documentation

- **[SCHEDULER_ARCHITECTURE.md](./SCHEDULER_ARCHITECTURE.md)** - Execution flow, design decisions, and the earlier BullMQ design

## License

Part of the TripThread application.
