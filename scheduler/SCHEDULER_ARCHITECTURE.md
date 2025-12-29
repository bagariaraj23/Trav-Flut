# Scheduler Architecture: Complete Engineering Deep Dive

> **Note:** For quick start, deployment, and usage instructions, see [README.md](./README.md).

## Table of Contents
1. [Overview: What Does the Scheduler Do?](#overview)
2. [How It Worked Before: BullMQ Architecture](#how-it-worked-before)
3. [How It Works Now: Cron-Based Architecture](#how-it-works-now)
4. [The Trigger Mechanism: What Runs It Every Hour?](#trigger-mechanism)
5. [Complete Execution Flow](#execution-flow)
6. [Engineering Trade-offs](#engineering-trade-offs)
7. [How It Powers Your Application](#how-it-powers-your-app)

---

## Overview: What Does the Scheduler Do?

The scheduler is responsible for **automatically transitioning trip statuses** based on time. Your application has three trip statuses:

- **UPCOMING**: Trip hasn't started yet (`startDate > now`)
- **ONGOING**: Trip is currently happening (`startDate <= now < endDate`)
- **ENDED**: Trip has finished (`endDate <= now`)

### Why This Matters

When a user creates a trip, they set `startDate` and `endDate`. The initial status is calculated at creation time, but as time passes, trips need to transition:
- A trip scheduled for tomorrow becomes ONGOING when today arrives
- An ongoing trip becomes ENDED when the end date passes

**The scheduler ensures these transitions happen automatically**, even when no user is actively using the app.

### Business Logic

The scheduler performs two main operations every hour:

1. **End trips that have passed their end date**
   - Finds all trips where `endDate <= now` and status is UPCOMING or ONGOING
   - Creates a "final post" summarizing the trip (media, locations, text entries)
   - Updates status to ENDED

2. **Start trips that have reached their start date**
   - Finds all trips where `startDate <= now < endDate` and status is UPCOMING
   - Updates status to ONGOING

---

## How It Worked Before: BullMQ Architecture

### BullMQ: What Is It?

**BullMQ** is a Redis-based job queue system. Think of it like a sophisticated task manager that:
- Stores jobs in Redis
- Manages workers that process jobs
- Handles scheduling, retries, and job state
- Provides job persistence and monitoring

### Architecture Diagram (Before)

```
┌─────────────────────────────────────────────────────────────┐
│                    Scheduler Service                         │
│  (Long-running Node.js process, stays alive 24/7)            │
└─────────────────────────────────────────────────────────────┘
                            │
                            │
        ┌───────────────────┴───────────────────┐
        │                                       │
        ▼                                       ▼
┌───────────────┐                      ┌───────────────┐
│  BullMQ Queue │                      │   Worker     │
│  (in Redis)   │                      │  (Processes)  │
└───────────────┘                      └───────────────┘
        │                                       │
        │                                       │
        │ 1. Schedules repeatable job          │
        │    every hour                         │
        │                                       │
        │ 2. Worker polls Redis                 │
        │    continuously (every few seconds)   │
        │                                       │
        │ 3. When job time arrives:             │
        │    - Worker picks up job             │
        │    - Executes updateTripStatuses()   │
        │    - Updates job status in Redis      │
        │                                       │
        └───────────────────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │   PostgreSQL  │
                    │   Database    │
                    └───────────────┘
```

### Detailed Flow (BullMQ)

#### 1. **Service Startup**
```typescript
// When scheduler starts:
1. Connect to Redis (ioredis)
2. Create BullMQ Queue named "tripStatus"
3. Create Worker that listens to the queue
4. Schedule a "repeatable job" that runs every hour
5. Service stays alive, waiting for jobs
```

#### 2. **Continuous Polling (The Problem)**
```typescript
// Every few seconds, BullMQ:
- Worker sends HEARTBEAT to Redis (proves it's alive)
- Worker polls Redis: "Any jobs for me?"
- Queue checks: "Is it time for the repeatable job?"
- Queue updates job metadata in Redis
- Worker checks for locks, job status, etc.

// This happens CONSTANTLY, even when no work to do!
// Result: Hundreds of Redis commands per minute
```

#### 3. **Job Execution (When Hour Strikes)**
```typescript
// When the scheduled time arrives:
1. BullMQ creates a job in Redis
2. Worker picks up the job
3. Worker executes: updateTripStatuses(prisma, now)
4. Worker updates job status: "completed" or "failed"
5. Worker stores result in Redis
6. Queue cleans up old jobs
```

### Redis Command Breakdown (Before)

**Per Minute (idle, no jobs):**
- Worker heartbeat: ~2 commands
- Poll for jobs: ~4 commands
- Queue metadata updates: ~2 commands
- Lock checks: ~2 commands
- **Total: ~10 commands/minute = 14,400/day = 432,000/month**

**Per Hour (when job runs):**
- Job creation: ~5 commands
- Job processing: ~10 commands
- Job completion: ~5 commands
- **Total: ~20 commands/hour**

**Monthly Total:**
- Idle overhead: ~432,000 commands
- Job executions: ~480 commands (20 × 24 hours × 30 days)
- **Grand Total: ~432,480 commands/month**

**Problem:** Even with zero trips, BullMQ burned through 86% of the 500k limit just from overhead!

---

## How It Works Now: Cron-Based Architecture

### Cron: What Is It?

**Cron** is a time-based job scheduler. It's like an alarm clock that runs a command at specified times. The scheduler is now a **simple script** that:
- Runs once when invoked
- Executes the update logic
- Exits immediately after completion

### Architecture Diagram (Now)

```
┌─────────────────────────────────────────────────────────────┐
│              External Cron Service                           │
│  (Railway Cron, GitHub Actions, or System Cron)               │
│                                                              │
│  Schedule: 0 * * * * (every hour at minute 0)               │
└─────────────────────────────────────────────────────────────┘
                            │
                            │ Every hour, triggers:
                            │ "cd scheduler && npm start"
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    Scheduler Script                          │
│  (Node.js process, runs once and exits)                     │
│                                                              │
│  1. main() → logSchedulerStartupInfo()                      │
│  2. main() → runTripStatusUpdate()                           │
│  3. runTripStatusUpdate() → updateTripStatuses()             │
│  4. Exit with code 0 (success) or 1 (failure)                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
                    ┌───────────────┐
                    │   PostgreSQL  │
                    │   Database    │
                    │  (Only this!) │
                    └───────────────┘
```

### Detailed Flow (Cron-Based)

#### 1. **Cron Trigger (Every Hour)**
```bash
# At 1:00 AM, 2:00 AM, 3:00 AM, etc.
# Cron service executes:
cd /path/to/scheduler
npm start  # or: node dist/index.js
```

#### 2. **Script Execution**
```typescript
// main() function runs:
1. Initialize Prisma client
2. Log startup information (no Redis needed)
3. Call runTripStatusUpdate()
4. Exit
```

#### 3. **Update Execution**
```typescript
// runTripStatusUpdate():
1. Connect to PostgreSQL
2. Get current time: now = new Date()
3. Call updateTripStatuses(prisma, now) with retry logic
4. Disconnect from database
5. Log results
6. Exit process
```

#### 4. **Status Update Logic**
```typescript
// updateTripStatuses(prisma, now):
1. Find trips to END:
   - WHERE endDate <= now AND status IN (UPCOMING, ONGOING)
   - For each: create final post (if doesn't exist)
   
2. Update statuses in transaction:
   - END trips: SET status = ENDED WHERE endDate <= now
   - START trips: SET status = ONGOING WHERE startDate <= now AND endDate > now
   
3. Return (no Redis involved!)
```

### Redis Command Breakdown (Now)

**Per Execution:**
- **0 Redis commands** ✅

**Monthly Total:**
- **0 commands** ✅

**Result:** All 500k commands available for API caching!

---

## The Trigger Mechanism: What Runs It Every Hour?

### The Key Insight

**The scheduler itself doesn't know about time.** It's just a script that runs when invoked. The **external cron service** is responsible for triggering it every hour.

### Deployment Options

The scheduler can be triggered by any external cron service. Common options:

- **Railway Cron** - Built-in cron service (recommended)
- **GitHub Actions** - Scheduled workflows
- **System Cron** - Linux/Mac cron daemon
- **Upstash QStash** - HTTP-based scheduling

For detailed deployment instructions, see [README.md](./README.md#deployment).

### Comparison: Who Triggers What?

| Aspect | BullMQ (Before) | Cron (Now) |
|--------|----------------|------------|
| **Trigger** | BullMQ's internal scheduler (Redis-based) | External cron service |
| **Process Lifecycle** | Long-running (24/7) | Short-lived (runs, exits) |
| **Redis Usage** | Constant polling | Zero |
| **Dependencies** | Redis required | Only database required |
| **Failure Recovery** | BullMQ retries automatically | Cron retries on next run |

---

## Complete Execution Flow

### Step-by-Step: What Happens Every Hour

```
┌─────────────────────────────────────────────────────────────┐
│ HOUR 0:00 - Cron Service Triggers                            │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 1. Cron executes: "cd scheduler && npm start"                │
│    - Starts new Node.js process                              │
│    - Loads environment variables                              │
│    - Runs: node dist/index.js                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 2. main() function starts                                     │
│    - Creates Prisma client                                   │
│    - Initializes Winston logger                              │
│    - Logs: "Starting scheduler (cron mode)..."              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 3. logSchedulerStartupInfo(prisma)                          │
│    - Tests database connection                                │
│    - Logs system info, config, environment                 │
│    - Verifies Prisma schema matches database                 │
│    - Logs: "STARTUP COMPLETE - All services ready"          │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 4. runTripStatusUpdate() begins                              │
│    - Records start time                                       │
│    - Logs: "Starting trip status update execution"           │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 5. Database Connection                                      │
│    - await prisma.$connect()                                  │
│    - Verifies PostgreSQL connection                           │
│    - Logs: "Database connection verified"                    │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 6. Get Current Time                                          │
│    - const now = new Date()                                   │
│    - Example: 2025-01-15T14:00:00.000Z                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 7. Execute with Retry Logic                                  │
│    - Wraps updateTripStatuses() in retryWithBackoff()        │
│    - Max 3 attempts, exponential backoff (1s, 2s, 4s)        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 8. updateTripStatuses(prisma, now) - Core Logic              │
│                                                               │
│    Step 8a: Find Trips to End                                │
│    ────────────────────────────                             │
│    SELECT id, destinations                                   │
│    FROM trips                                                │
│    WHERE endDate <= '2025-01-15T14:00:00'                    │
│      AND status IN ('UPCOMING', 'ONGOING')                   │
│                                                               │
│    Step 8b: Create Final Posts                               │
│    ────────────────────────────                             │
│    For each trip found:                                      │
│      - Check if final post exists                            │
│      - If not, create summary post with:                     │
│        * Text entries count                                 │
│        * Media entries (first 6)                              │
│        * Location entries count                              │
│        * Generated summary text                              │
│                                                               │
│    Step 8c: Update Statuses (Transaction)                     │
│    ────────────────────────────                             │
│    BEGIN TRANSACTION;                                        │
│                                                               │
│    -- End trips that have passed                             │
│    UPDATE trips                                              │
│    SET status = 'ENDED'                                      │
│    WHERE endDate <= '2025-01-15T14:00:00'                    │
│      AND status IN ('UPCOMING', 'ONGOING');                  │
│                                                               │
│    -- Start trips that have begun                            │
│    UPDATE trips                                              │
│    SET status = 'ONGOING'                                    │
│    WHERE startDate <= '2025-01-15T14:00:00'                  │
│      AND endDate > '2025-01-15T14:00:00'                     │
│      AND status = 'UPCOMING';                                │
│                                                               │
│    COMMIT;                                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 9. Success Logging                                           │
│    - Calculate duration: Date.now() - startTime              │
│    - Log: "Trip status update completed successfully"         │
│    - Log duration and timestamp                              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 10. Cleanup                                                  │
│     - await prisma.$disconnect()                             │
│     - Log: "Database connection closed"                        │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│ 11. Exit                                                     │
│     - process.exit(0)  # Success code                         │
│     - Process terminates                                     │
│     - Cron service logs completion                           │
└─────────────────────────────────────────────────────────────┘
```

### Error Handling Flow

```
If error occurs at any step:
│
├─> Retry Logic (if transient error)
│   ├─> Wait 1 second, retry
│   ├─> Wait 2 seconds, retry
│   └─> Wait 4 seconds, retry
│
├─> If all retries fail:
│   ├─> Log error with stack trace
│   ├─> Disconnect from database
│   └─> Exit with code 1 (failure)
│
└─> Cron service logs failure
    └─> Next run will attempt again in 1 hour
```

---

## Engineering Trade-offs

### BullMQ Approach (Before)

**Pros:**
- ✅ Built-in retry logic
- ✅ Job persistence (survives restarts)
- ✅ Job monitoring and UI
- ✅ Automatic failure handling
- ✅ Can scale workers horizontally

**Cons:**
- ❌ Requires Redis (additional dependency)
- ❌ Constant polling overhead
- ❌ Complex setup
- ❌ Higher resource usage (long-running process)
- ❌ Redis command budget consumption

### Cron Approach (Now)

**Pros:**
- ✅ Zero Redis dependency
- ✅ Simple architecture
- ✅ Lower resource usage (runs only when needed)
- ✅ Easy to debug (single execution)
- ✅ No overhead between runs
- ✅ All Redis budget for API caching

**Cons:**
- ❌ No built-in job persistence (but not needed for hourly cron)
- ❌ Manual retry logic (but we implemented it)
- ❌ No job monitoring UI (but logs are sufficient)
- ❌ If cron fails, must wait for next run (acceptable for hourly)

### Why Cron Wins for This Use Case

1. **Simple requirement**: Run once per hour, no complex scheduling
2. **No job queue needed**: We're not queuing user requests
3. **Database is source of truth**: No need for Redis job storage
4. **Cost optimization**: Free Redis budget for user-facing features
5. **Reliability**: Fewer moving parts = fewer failure points

---

## How It Powers Your Application

### User Journey: From Creation to Completion

#### 1. **User Creates Trip**
```typescript
// User creates trip via API: POST /api/trips
{
  title: "Paris Adventure",
  startDate: "2025-02-01T00:00:00Z",
  endDate: "2025-02-07T23:59:59Z",
  destinations: ["Paris", "Versailles"]
}

// API calculates initial status:
const now = new Date();
const status = startDate > now ? "UPCOMING" : "ONGOING";

// Trip saved with status = "UPCOMING"
```

#### 2. **Time Passes...**
```
Day 1: Trip status = "UPCOMING" (scheduler runs, no change)
Day 2: Trip status = "UPCOMING" (scheduler runs, no change)
...
February 1: Trip status = "UPCOMING" (scheduler runs, no change)
```

#### 3. **Scheduler Runs at 1:00 AM on February 1st**
```typescript
// Scheduler executes:
const now = new Date("2025-02-01T01:00:00Z");

// Finds trip where:
//   startDate <= now (2025-02-01T00:00:00 <= 2025-02-01T01:00:00) ✅
//   endDate > now (2025-02-07T23:59:59 > 2025-02-01T01:00:00) ✅
//   status = "UPCOMING" ✅

// Updates: status = "ONGOING"
```

#### 4. **User Sees Trip as "ONGOING"**
```typescript
// User opens app, fetches trips: GET /api/trips
// API returns trip with status = "ONGOING"
// Mobile app shows: "Trip is ongoing!"
```

#### 5. **User Adds Entries During Trip**
```typescript
// User posts photos, locations, text during trip
// All entries saved with tripId
// Trip status remains "ONGOING"
```

#### 6. **Scheduler Runs at 1:00 AM on February 8th**
```typescript
// Scheduler executes:
const now = new Date("2025-02-08T01:00:00Z");

// Finds trip where:
//   endDate <= now (2025-02-07T23:59:59 <= 2025-02-08T01:00:00) ✅
//   status = "ONGOING" ✅

// Creates final post:
//   - Summarizes all entries
//   - Curates first 6 media items
//   - Generates summary text

// Updates: status = "ENDED"
```

#### 7. **User Sees Completed Trip**
```typescript
// User opens app, sees trip with status = "ENDED"
// Final post is displayed with summary
// Trip appears in "Past Trips" section
```

### Real-World Example Timeline

```
Timeline for "Paris Adventure" trip:

Jan 15, 2025 10:00 AM
├─> User creates trip
├─> startDate: Feb 1, 2025
├─> endDate: Feb 7, 2025
└─> status: "UPCOMING" ✅

Jan 15 - Jan 31
├─> Scheduler runs every hour
├─> Checks: startDate > now? Yes
└─> No status change

Feb 1, 2025 1:00 AM (Scheduler Run #1)
├─> Checks: startDate <= now? Yes (Feb 1 <= Feb 1)
├─> Checks: endDate > now? Yes (Feb 7 > Feb 1)
├─> Updates: status = "ONGOING" ✅
└─> User sees trip as active

Feb 1 - Feb 7
├─> User posts 15 photos
├─> User shares 8 locations
├─> User writes 5 text entries
└─> status remains "ONGOING"

Feb 8, 2025 1:00 AM (Scheduler Run #2)
├─> Checks: endDate <= now? Yes (Feb 7 <= Feb 8)
├─> Creates final post:
│   ├─> Summary: "Amazing trip to Paris, Versailles! 
│   │            Visited 8 amazing places. 
│   │            Shared 5 memorable moments. 
│   │            Captured 15 beautiful memories."
│   └─> Curated media: [first 6 photos]
├─> Updates: status = "ENDED" ✅
└─> User sees completed trip with final post
```

### Integration Points

#### API Endpoints That Depend on Status

1. **GET /api/trips**
   - Filters trips by status
   - Returns "upcoming", "ongoing", "ended" trips separately

2. **GET /api/trips/[id]**
   - Returns trip with current status
   - Status determines UI behavior

3. **POST /api/trips/[id]/entries**
   - Only allows entries for ONGOING trips
   - Rejects entries for ENDED trips

4. **POST /api/trips/[id]/end**
   - Manual trip ending (alternative to scheduler)
   - Creates final post immediately

### Why This Matters

**Without the scheduler:**
- Trips would never automatically transition
- Users would see "UPCOMING" trips forever
- Final posts would never be created automatically
- App would feel "broken" or "stuck"

**With the scheduler:**
- ✅ Trips automatically become active when they start
- ✅ Trips automatically complete when they end
- ✅ Final posts are created automatically
- ✅ App feels "alive" and responsive
- ✅ Users don't need to manually manage status

---

## Summary

### The Big Picture

1. **What it does**: Automatically updates trip statuses based on time
2. **How it runs**: External cron service triggers script every hour
3. **What it uses**: Only PostgreSQL database (no Redis)
4. **Why it matters**: Keeps your app's trip statuses accurate and up-to-date

### Key Takeaways

- **Before**: BullMQ managed scheduling internally, but consumed Redis budget
- **Now**: External cron triggers simple script, zero Redis usage
- **Result**: All Redis budget available for API caching, simpler architecture
- **Impact**: App works the same for users, but more efficient behind the scenes

### Next Steps

1. Set up cron service (see [README.md](./README.md#deployment))
2. Configure schedule: `0 * * * *` (every hour)
3. Deploy scheduler code
4. Monitor logs to verify execution
5. Enjoy zero Redis usage from scheduler! 🎉

---

## FAQ

- **Q: What if the scheduler fails?**
  A: It will retry on the next hourly run. For critical failures, check logs.

- **Q: Can I run it manually?**
  A: Yes! Just run `npm start` in the scheduler directory.

- **Q: What if I need it to run more frequently?**
  A: Change the cron schedule (e.g., `*/30 * * * *` for every 30 minutes).

- **Q: Does it work across timezones?**
  A: Yes, it uses UTC timestamps, so it works globally.

For more practical questions, see [README.md](./README.md#troubleshooting).


