# Scheduler and operations

The scheduler is a second program with the same database and none of the API's Redis, HTTP, or WebSocket machinery. Operations around it are Docker, health, email, and a few scripts.

## Scheduler

Files: `scheduler/src/index.ts`, `tripStatus.ts`, `tripEnd.ts`, `startup-logger.ts`. Narrative design: `scheduler/SCHEDULER_ARCHITECTURE.md` and `scheduler/MIGRATION_NOTES.md`.

`index.ts` loads env, constructs Prisma, logs database health, calls `updateTripStatuses`, and exits. Exit is the feature. Cron, GitHub Actions, or the Compose shell starts the next run. Nothing in this process stays resident, so it cannot leak a Redis connection or a BullMQ worker.

`startup-logger.ts` states there is no Redis dependency. That is checked by reading the scheduler sources: they import Prisma and the duplicated end-instant helper, not `src/lib/redis.ts`.

### What one run does

`updateTripStatuses(prisma, now)` in `tripStatus.ts`:

1. Load trips in `UPCOMING` or `ONGOING` whose stored `endDate` is at or before now, plus `UPCOMING` trips whose `startDate` is at or before now. This is a coarse fetch. Indexes `(status, endDate)` and `(status, startDate)` exist for it.
2. Recompute with `scheduledEndInstant` (copy in `tripEnd.ts`). Midnight ends expand to 23:59:59.999 in `scheduleTimezone`. A trip with `endDate` null is not in the end batch.
3. End batch, one transaction per trip: if no `TripFinalPost` exists, insert one (a shorter template than `TripFinalizerService`), then set `status = ENDED`. The insert does not set `generationStatus`, so the column default `DRAFT` applies.
4. Start batch: `updateMany` the filtered `UPCOMING` ids to `ONGOING`.
5. Return `{ endedCount, ongoingCount, nowIso }`.

The API does not wait for this. `syncViewerTripSchedule` and `syncTripById` apply the same status rules on read, and when they end a trip they call `TripFinalizerService`, which writes `READY` and a richer summary. A trip that nobody opens still ends, because cron is the backstop. A trip that somebody opens may end earlier and with a better draft. See [Thread and final posts](./06-thread-and-final-posts.md).

### How it is invoked

| Place | Cadence |
| --- | --- |
| Documented production cron | `0 * * * *` (hourly), from `scheduler/README.md` and the comment in `tripStatus.ts` |
| Docker Compose | After the API healthcheck passes, loop every `SCHEDULER_INTERVAL_SECONDS` (default 300) |
| A developer | `npx tsx src/index.ts` inside `scheduler/`, once |

Docker is a convenience loop around the same one-shot script. It is not a long-running worker with its own queue.

## Docker

`docker-compose.yml` (full local stack) and `docker-compose.dev.yml` (Postgres only). Details: `DOCKER_SETUP.md`, `QUICKSTART.md`.

| Service | Role |
| --- | --- |
| `postgres-dev` | Port 5432 |
| `postgres-test` | Port 5433 |
| `backend` | `node server.cjs` on port 3000. REST and `/chat` |
| `web` | Flutter web, nginx port 8080, proxies API, chat, share, well-known, Next assets, reset pages |
| `scheduler` | The loop described above |

`scripts/docker-entrypoint.sh` waits for Postgres, runs `prisma migrate deploy`, baselines a volume that was previously created with `db push`, then execs the command. Production hosting is Railway / Railpack, not this Dockerfile. The image is for local parity.

`SHARE_LINK_BASE_URL` is passed into the backend so share links in emails and API responses point at the host the web container serves.

## Health

`GET /api/health` pings Postgres, returns process metrics, the in-memory `PerformanceMonitor` (last 100 timings, warn over 1 second), and `ErrorTracker` (last 1000 errors). The external-service map on the payload is empty. Health does not call Cloudinary, Mapbox, SendGrid, or Redis, and it does not upgrade to WebSocket. A green healthcheck means the process is up and Postgres answers.

`PerformanceMonitor` timers are placed on the hot feed and discover handlers (`get_home_feed` and the discover equivalent). They are process-local. A restart clears them. There is no Sentry, Datadog, or OpenTelemetry exporter in the repo.

## Email

Only SendGrid, only two messages: password reset and "your password changed". Implementation: `src/lib/services/email.ts`. If `SENDGRID_API_KEY` is unset, send is a no-op and the API still returns success for forgot-password. That is safe for enumeration and unsafe for a misconfigured production deploy, because the user hears nothing. `MAIL_FROM` defaults to `no-reply@your-domain` and should be a verified sender. `SENDGRID_DEBUG` turns on extra logging.

No other mail is sent. Follows, comments, and trip invites are in-app notifications only.

## Scripts

| Script | Purpose |
| --- | --- |
| `src/scripts/cleanupExpiredPasswordResets.ts` | Delete used or expired reset rows older than `RESET_RETENTION_DAYS` (7) |
| `src/scripts/cleanup-orphan-media.ts` | List or `--apply` delete media with no parent, older than `--hours` (24), max 500 |
| `src/scripts/seed.ts` | Dev seed |
| `scripts/build-server.mjs` | Bundle `chat-ws.ts` to `dist/chat-ws.cjs` at image build time |
| `scripts/docker-entrypoint.sh` | Migrate then boot |

Password-reset cleanup and media cleanup are not inside the trip scheduler. Running them on the same cron host is an operator choice. They are separate so a failure in Cloudinary deletes cannot block trip status, and so the scheduler image does not need Cloudinary credentials.

## Monitoring gaps that are real

- No trace across the phone, the API, and Cloudinary. A failed confirm is a client log plus an API log.
- Cache hit rate is the in-process counter behind `/api/admin/cache/metrics`, not a hosted dashboard.
- Chat liveness is not in `/api/health`.
- Security events for password reset do not persist, because the type strings are outside the enum. Rate-limit events do persist. See [Security](./16-security-middleware.md).
